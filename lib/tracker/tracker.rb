#!/usr/bin/ruby
require 'json'
require 'logger'
require 'rubygems'
require 'ipaddr'
require 'set'
require_relative 'protocol_udp'
require_relative 'connection_ids'

class Peer
  attr_reader :id
  attr_accessor :ip, :port, :timestamp, :completed

  def initialize(id, ip, port, timestamp, completed = false)
    @id, @ip, @port, @timestamp, @completed = id, ip, port, timestamp, completed
  end

  #def ==(other)
  #  @id == other.id # && @ip == other.ip && @port == other.port
  #end

  #def eql?(other)
  #  @id == other.id # && @ip == other.ip && @port == other.port
  #end

  # def hash
  #  @id.hash
    # [@id, @ip, @port].hash
  #end

  def to_json(*args)
    {
      JSON.create_id => self.class.name,
      'data' => [@id, @ip, @port, @timestamp, @completed]
    }.to_json(*args)
  end

  def self.json_create(h)
    new(*h['data'])
  end
end


class Tracker < Periodic
  PERIODIC_INTERVAL = 60
  PEER_TIMEOUT      = 3 * 86400

  ANNOUNCE_INTERVAL = 30
  attr_reader :socket

  def initialize(options = {})
    super(PERIODIC_INTERVAL)
    @log_dir = options[:log_dir]
    @port    = options[:port]
    @storage = options[:storage]

    initialize_logger()
    @peers = Hash.new()
    @connection_ids = ConnectionIds.new(:logger => @logger)
    @socket = UDPSocket.new
    @socket.bind("0.0.0.0", @port)
    load_peers()
  end

  def initialize_logger()
    FileUtils.mkdir_p(@log_dir)
    path = File.join(@log_dir, "tracker.log")
    @logger = Logger.new(path, 5, 104857600)
    @logger.sev_threshold = Logger::DEBUG
  end

  def load_peers()
    @storage.each_peer { |info_hash, id, peer|
      peer = JSON.parse(peer, create_additions: true)
      if peers = @peers[info_hash]
        peers[id] = peer
      else
        @peers[info_hash] = {id => peer}
      end
    }
  end

  def handle
    begin
      bin, inet_address = @socket.recvfrom_nonblock(65536)
      port = inet_address[1]
      ip   = inet_address[3]
      msg = ProtocolUdp.decode_server_query(bin)
      if reply = handle_message(msg, ip, port)
        @logger.info("out: " + reply.to_s)
        @socket.send(ProtocolUdp.encode(reply), 0, ip, port)
      end
    rescue UdpProtocolException => e
      @logger.warn(e.to_s)
      @socket.send(Protocol.encode(e), 0, ip, port)
    rescue IO::WaitReadable
    end
  end

  def handle_message(msg, ip, port)
    case msg
    when ConnectQuery
      @connection_ids.with_connection_id { |connection_id|
        ConnectReply.new(msg.transaction_id, connection_id)
      }
    when AnnounceQuery
      if @connection_ids.is_valid(msg.connection_id)
        handle_message_announce_query(msg, ip, port)
      end
    when ScrapeQuery
      if @connection_ids.is_valid(msg.connection_id)
        # ScrapeReply.new(connection_id, info)
      end
    end
  end

  def handle_message_announce_query(msg, ip, port)
    ip       = msg.ip == 0 ? ip : IPAddr.new(ip, Socket::AF_INET)
    num_want = msg.num_want == -1 ? 25 : msg.num_want
    case msg.event
    when 0
      # none
      insert(msg.peer_id, ip, port, msg.info_hash, false)
    when 1
      # completed
      insert(msg.peer_id, ip, port, msg.info_hash, true)
    when 2
      # started
      insert(msg.peer_id, ip, port, msg.info_hash, false)
    when 3
      # stopped
      remove(msg.peer_id, ip, port, msg.info_hash)
    end
    peers = get_peers(msg.info_hash, num_want)
    seeders  = peers.count { |peer| peer.completed }
    leechers = peers.count { |peer| !peer.completed }
    AnnounceReply.new(msg.transaction_id, ANNOUNCE_INTERVAL, leechers, seeders, peers)
  end


  def mark_as_info_hash(info_hash)
    @logger.info("mark infohash #{info_hash}")
  end

  def get_peers(info_hash, number)
    if peers = @peers[info_hash]
      peers.values.shuffle.take(number)
    else
      []
    end
  end

  def insert(id, ip, port, info_hash, completed)
   if peers = @peers[info_hash]
     if peer = peers[id]
       peer.ip = ip
       peer.port = port
       peer.timestamp = Time.now.to_i
       peer.completed = completed
       @storage.set_peer(info_hash, id, peer.to_json)
     else
       peer = Peer.new(id, ip, port, Time.now.to_i, completed)
       peers[id] = peer
       @storage.set_peer(info_hash, id, peer.to_json)
     end
   else
     peer = Peer.new(id, ip, port, Time.now.to_i, completed)
     @peers[info_hash] = {id => peer}
     @storage.set_peer(info_hash, id, peer.to_json)
   end
  end

  def remove(id, ip, port, info_hash)
    if peers = @peers[info_hash]
      if peer = peers[id]
        @storage.delete_peer(info_hash, id)
      end
    end
  end

  def run_periodic
    garbage_collect_connection_ids()
    garbage_collect()
  end

  def garbage_collect_connection_ids()
    @connection_ids.garbage_collect()
  end

  def garbage_collect()
    now = Time.now.to_i
    count_tot = 0
    count_del = 0
    info_hashes = Hash.new(0)
    @storage.each_peer { |info_hash, id, peer|
      peer = JSON.parse(peer, create_additions: true)
      if peer.timestamp + PEER_TIMEOUT < now
        @storage.delete_peer(info_hash, id)
        count_del += 1
      else
        count_tot += 1
        info_hashes[info_hash] = info_hashes[info_hash] + 1
      end
    }
    puts "number of peers = " + count_tot.to_s
    puts "peers garbage collected = " + count_del.to_s
    puts info_hashes.to_a
      .sort { |a,b| b[1] <=> a[1] }
      .take(15)
      .map { |a|
      puts a[1]
      'magnet:?xt=urn:btih:' + a[0]
    }
  end
end
