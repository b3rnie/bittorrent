#!/usr/bin/ruby

require 'logger'
require 'rubygems'
require 'resolv'
require 'securerandom'
require 'socket'
require 'bundler/setup'
require_relative 'protocol'
require_relative 'queries'
require_relative 'storage'
require_relative 'routing'
require_relative 'tokens'
require_relative '../tracker/tracker'
require_relative 'types'

class DhtNode
  attr_reader :instance
  attr_reader :socket

  def initialize(options = {})
    @instance = options[:instance]
    @storage  = options[:storage]
    @tracker  = options[:tracker]
    @log_dir  = options[:log_dir]
    @port     = options[:port]

    initialize_logger()
    initialize_id()

    @routing_table = RoutingTable.new(:logger  => @logger,
                                      :instance => @instance,
                                      :node_id => @my_node_id,
                                      :storage => @storage)
    @queries       = Queries.new(:logger => @logger)
    @tokens        = Tokens.new(:logger => @logger)
    @socket        = UDPSocket.new
    @socket.bind("0.0.0.0", @port)
  end

  def initialize_logger()
    FileUtils.mkdir_p(@log_dir)
    path = File.join(@log_dir, "#{@instance}-dht.log")
    @logger = Logger.new(path, 5, 104857600)
    # @logger = Logger.new(STDOUT)
    @logger.sev_threshold = Logger::DEBUG
  end

  def initialize_id()
    if @my_node_id = @storage.get_config(@instance, 'id')
      @logger.info("using node id: " + @my_node_id)
    else
      @my_node_id = Conversions.binary_id_to_hex(SecureRandom.random_bytes(20))
      @storage.set_config(@instance, 'id', @my_node_id)
      @logger.info("generated node id: " + @my_node_id)
    end
  end

  def periodic
    @queries.periodic
    @tokens.periodic
    pings = @routing_table.periodic
    if pings
      pings.each { |id,ip,port|
        query = @queries.with_tid { |tid|
          PingQuery.new(tid, @my_node_id)
        }
        @logger.info("out: " + query.to_s)
        @socket.send(Protocol.encode(query), 0, ip, port)
        @routing_table.record_query_out(id)
      }
    end
  end

  def handle
    begin
      bin, inet_address = @socket.recvfrom_nonblock(65536)
      port = inet_address[1]
      ip   = inet_address[3]
      if port !=0
        msg = Protocol.decode(bin)
        if reply = handle_message(msg, ip, port)
          @logger.info("out: " + reply.to_s)
          @socket.send(Protocol.encode(reply), 0, ip, port)
        end
      end
    rescue GenericException,
           # ServerException,
           ProtocolException,
           MethodUnknownException => e
      @logger.warn(e.to_s)
      @socket.send(Protocol.encode(e), 0, ip, port)
    rescue IO::WaitReadable
    end
  end

  def send_bootstrap_query()
    [#"dht.transmissionbt.com",
     #"router.utorrent.com",
     "router.bittorrent.com"].each { |host|
      query = @queries.with_tid { |tid|
        FindNodeQuery.new(tid, @my_node_id, @my_node_id)
      }
      @socket.send(Protocol.encode(query), 0, Resolv.getaddress(host), 6881)
    }
  end

  def send_find_node_query()
    @routing_table.get_closest_nodes(@my_node_id).each { |id,ip,port|
      query = @queries.with_tid { |tid|
        FindNodeQuery.new(tid    = tid,
                          id     = @my_node_id,
                          target = @my_node_id)
      }
      @socket.send(Protocol.encode(query), 0, ip, port)
    }
  end

  def handle_message(msg, ip, port)
    is_query(msg) ?
      handle_message_query(msg, ip, port) :
      handle_message_reply(msg, ip, port)
  end

  def handle_message_query(msg, ip, port)
    @logger.info("in: " + msg.to_s)
    @routing_table.insert_node(msg.id, ip, port)
    @routing_table.record_query_in(msg.id)
    @routing_table.record_reply_out(msg.id)
    case msg
    when PingQuery
      PingReply.new(msg.tid, @my_node_id)
    when FindNodeQuery
      FindNodeReply.new(msg.tid,
                        @my_node_id,
                        @routing_table.get_closest_nodes(msg.target))
    when GetPeersQuery
      # @tracker.mark_as_info_hash(msg.info_hash)
      peers = @tracker.get_peers(msg.info_hash, 16)
      GetPeersReply.new(msg.tid,
                        @my_node_id,
                        @tokens.get_token,
                        peers,
                        peers.empty? ? @routing_table.get_closest_nodes(msg.info_hash) : [])
    when AnnouncePeerQuery
      if @tokens.is_valid(msg.token)
        @tracker.insert(msg.id,
                        ip,
                        msg.implied_port ? port : msg.port,
                        msg.info_hash,
                        false)
        AnnouncePeerReply.new(msg.tid, @my_node_id)
      else
        raise ProtocolException.new(msg.tid), "bad token"
      end
    end
  end

  def handle_message_reply(msg, ip, port)
    if query = @queries.get_query(msg.tid)
      if is_error(msg)
        @logger.error("in: " + msg.to_s)
      else
        reply = Protocol.build_reply(query, msg)
        @logger.info("in: " + reply.to_s)
        @routing_table.insert_node(reply.id, ip, port)
        @routing_table.record_reply_in(reply.id)
        case reply
        when PingReply
        when FindNodeReply
          reply.nodes.each { |id,ip,port|
            @routing_table.insert_node(id, ip, port)
          }
        when GetPeersReply
          if reply.values
            reply.values.each { |peer_ip, peer_port|
              @tracker.insert(nil,
                              peer_ip,
                              peer_port,
                              query.info_hash)
            }
          end
          if reply.nodes
            reply.nodes.each { |id, node_ip, node_port|
              @routing_table.insert_node(id, node_ip, node_port)
            }
          end
        when AnnouncePeerReply
        end
      end
    else
      @logger.warn("unexpected reply: " + msg.to_s)
    end
    nil
  end
end

class Server
  def initialize(options = {})
    @instances = options[:instances]
    @log_dir   = options[:log_dir]
    @data_dir  = options[:data_dir]

    @storage = Storage.new(:data_dir => @data_dir)
    @tracker = Tracker.new(:log_dir => @log_dir, :port => 7043, :storage => @storage)
    @nodes   = @instances.map { |instance|
      DhtNode.new(:instance => instance[:instance],
                  :storage  => @storage,
                  :tracker  => @tracker,
                  :log_dir  => @log_dir,
                  :port     => instance[:port])
    }
  end

  def bootstrap(instance)
    @nodes[@nodes.index { |node| node.instance == instance }].send_bootstrap_query()
  end

  def find_node(instance)
    @nodes[@nodes.index { |node| node.instance == instance }].send_find_node_query()
  end

  def run()
    while true
      sockets = @nodes.map { |node| node.socket } + [@tracker.socket]
      IO.select(sockets, [], [], 5)
      @tracker.periodic
      @nodes.each { |node|
        node.periodic
        node.handle
      }
      @tracker.handle
      # fixme only call handle if there is any data available!
    end
  end
end
