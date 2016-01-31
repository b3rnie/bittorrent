#!/usr/bin/ruby
require 'json'
require_relative 'periodic'

class Node
  attr_accessor :ip, :port
  attr_accessor :id, :queries_in, :queries_out, :replies_in, :replies_out

  STATUS_GOOD         = 0
  STATUS_BAD          = 1
  STATUS_QUESTIONABLE = 2

  TIMEOUT = 15 * 60

  def initialize(id, ip, port, queries_in = [], queries_out = [],
                 replies_in = [], replies_out = [])
    @id, @ip, @port = id, ip, port
    @queries_in, @queries_out  = queries_in, queries_out
    @replies_in, @replies_out  = replies_in, replies_out
  end

  def record_query_in
    @queries_in << Time.now.to_i
    @queries_in = @queries_in.last(2)
  end

  def record_query_out
    @queries_out << Time.now.to_i
    @queries_out = @queries_out.last(2)
  end

  def record_reply_in
    @replies_in << Time.now.to_i
    @replies_in = @replies_in.last(2)
  end

  def record_reply_out
  end

  def last_query
    @queries.last
  end

  def status
    now = Time.now.to_i
    if (@replies_in.last && @replies_in.last+Node::TIMEOUT > now)
      # Node has responded to our queries in the last 15 minutes
      Node::STATUS_GOOD
    elsif (@replies_in.last &&
           @queries_out.last &&
           @queries_out.last + Node::TIMEOUT > now)
      # Node has responded to our queries at least once AND has sent
      # us a query in the last 15 minutes
      Node::STATUS_GOOD
    elsif (@queries_out.size >= 2 &&
           @queries_out.all? { |timestamp|
             @replies_in.last.nil? || @replies_in.last < timestamp
           })
      # Node has failed to respond to multiple queries in a row
      Node::STATUS_BAD
    else
      Node::STATUS_QUESTIONABLE
    end
  end

  def to_json(*args)
    {
      JSON.create_id => self.class.name,
      'data' => [@id, @ip, @port, @queries_in, @queries_out, @replies_in, @replies_out]
    }.to_json(*args)
  end

  def to_s
    self.class.to_s + ": @id=#{@id}, @queries_in=#{@queries_in}, @queries_out=#{@queries_out}, @replies_in=#{@replies_in} @replies_out=#{@replies_out}"
  end

  def self.json_create(h)
    new(*h['data'])
  end
end

class RoutingTable < Periodic
  MAX_BUCKET_SIZE   = 8
  PING_INTERVAL     = 300
  PERIODIC_INTERVAL = 30

  def initialize(options = {})
    super(PERIODIC_INTERVAL)
    @logger     = options[:logger]
    @instance   = options[:instance]
    @my_node_id = options[:node_id]
    @storage    = options[:storage]

    @buckets    = Array.new(160) { [] }
    @nodes      = {}
    load_routing_table()
  end

  def insert_node(id, ip, port)
    find_or_create_node(id, ip, port)
  end

  def record_query_in(id)
    with_node(id) { |node| node.record_query_in }
  end

  def record_query_out(id)
    with_node(id) { |node| node.record_query_out }
  end

  def record_reply_in(id)
    with_node(id) { |node| node.record_reply_in }
  end

  def record_reply_out(id)
    with_node(id) { |node| node.record_reply_out }
  end

  def run_periodic
    store_routing_table()
    now = Time.now.to_i
    nodes = @buckets.flatten.select { |node|
      (node.status == Node::STATUS_QUESTIONABLE ||
       node.status == Node::STATUS_BAD) &&
        (node.queries_out.last.nil? ||
         node.queries_out.last + PING_INTERVAL <= now) &&
        node.port != 0
    }
    nodes.map { |node|
      [node.id, node.ip, node.port]
    }.shuffle.take(MAX_BUCKET_SIZE)
  end

  def get_closest_nodes(target, n = 16)
    nodes      = []
    bucket_idx = id_to_bucket(target)
    while nodes.size < n && bucket_idx >= 0
      nodes += @buckets[bucket_idx]
      bucket_idx -= 1
    end
    nodes[0,n].map { |node| [node.id, node.ip, node.port] }
  end

  def size
    @buckets.flatten.length
  end

  private
  def with_node(id)
    if node = @nodes[id]
      yield(node)
    end
  end

  def find_or_create_node(id, ip, port)
    if node = @nodes[id]
      node
    else
      bucket = @buckets[id_to_bucket(id)]
      if bucket.size >= RoutingTable::MAX_BUCKET_SIZE
        if (idx = bucket.find_index { |node|
              node.status == Node::STATUS_BAD
            })
          @nodes.delete([bucket[idx].id])
          bucket.delete_at(idx)
        end
      end

      if bucket.size < RoutingTable::MAX_BUCKET_SIZE
        node = Node.new(id, ip, port)
        @nodes[id] = node
        bucket << node
        node
      end
    end
  end

  def id_to_bucket(id)
    distance = Conversions.hex_id_to_int(Conversions.xor_hex(@my_node_id, id))
    n = 0
    while (distance & (1 << (159 - n))) == 0 && n != 159
      n += 1
    end
    n
  end

  def store_routing_table()
    @buckets.each_with_index { |bucket, index|
      @storage.set_routing_table(@instance, index, bucket.to_json)
    }
  end

  def load_routing_table()
    @buckets.each_with_index { |bucket, index|
      if old_bucket = @storage.get_routing_table(@instance, index)
        old_bucket = JSON.parse(old_bucket, create_additions: true)
        old_bucket.each { |node|
          puts node
          bucket << node
          @nodes[node.id] = node
        }
      end
    }
  end
end
