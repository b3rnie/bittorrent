require 'resolv'
require 'set'
require 'socket'
require 'thread'
require_relative '../tracker/protocol_udp'


class Tracker
  RESOLVER_RETRY_INTERVAL = 60 * 5  # 5 minutes
  RESOLVER_MAX_QUEUE_SIZE = 10
  MIN_SCRAPE_INTERVAL     = 60 * 45 # 45 minutes
  MIN_ANNOUNCE_INTERVAL   = 60 * 15 # 15 minutes

  class Torrent
    class Tracker
      attr_reader :host, :port
      def initialize(host, port)
        @host = host
        @port = port
      end
    end

    attr_reader :stats, :trackers
    def initialize(stats, trackers)
      @stats    = stats
      @trackers = trackers.map { |tracker|
        uri = URI(tracker)
        if uri.scheme == "udp"
          Tracker.new(uri.host, uri.port)
        end
      }.compact
    end
  end

  attr_reader :socket

  def initialize(options = {})
    @logger          = options[:logger]
    @my_node_id      = options[:my_node_id]
    @port            = options[:port]
    @torrents        = {} # info_hash -> list of trackers and status
    @peers           = {} # info_hash -> peers
    @trackers        = []
    @resolver_in     = Queue.new
    @resolver_out    = Queue.new
    @resolver_thread = start_resolver_thread # multiple at some point
    @socket          = UDPSocket.new
    @socket.bind("0.0.0.0", @port)
  end

  def ready_to_write?; false end
  def ready_to_read?;  true  end

  def try_read
    while true
      begin
        bin, inet_address = @socket.recvfrom_nonblock(0xFFFF)
        port = inet_address[1]
        ip   = inet_address[3]
        begin
          handle_incoming(ip, port, bin)
        rescue TrackerProtocolUDP::ProtocolException => e
          @logger.error(e.to_s)
        end
      rescue IO::WaitReadable
        break
      end
    end
  end

  def update
    handle_resolver_done
    handle_resolver_retries
    handle_announce
  end

  def start_announce(info_hash, stats, trackers)
    if @torrents.has_key?(info_hash)
      fail "already announcing #{info_hash}"
    end
    torrent = Torrent.new(stats, trackers)
    torrent.trackers.each { |t|
      unless find_tracker_by_host_port(t.host, t.port)
          @logger.info("adding tracker #{t.host}:#{t.port}")
          tracker = TrackerUDP.new(t.host, t.port)
          @trackers.push(tracker)
          if @resolver_in.size < RESOLVER_MAX_QUEUE_SIZE
            tracker.log(TrackerUDP::EVENT_RESOLVE_ATTEMPT)
            @resolver_in.push([t.host, t.port])
          end
      end
    }
    @torrents[info_hash] = torrent
  end

  def stop_announce(info_hash)
    if torrent = @torrents[info_hash]
      # find all trackers we are announcing to and send stop
      torrent.trackers.each { |t|
        tracker = find_tracker_by_host_port(t.host, t.port)
        # TODO
      }
    else
      fail "not announcing #{info_hash}"
    end
  end

  def get_peer(info_hash)
    if set = @peers[info_hash]
      if peer = set.first
        set.delete(peer)
        peer
      end
    end
  end

  private
  # resolving
  def start_resolver_thread
    Thread.new {
      while true
        host, port = @resolver_in.pop
        begin
          @logger.debug("resolving #{host}")
          ip = Resolv.getaddress(host)
          @resolver_out.push([host, port, ip])
        rescue => e
          @logger.error("resolving #{host} failed: " + e.to_s)
        end
      end
    }
  end

  def resolver_thread_alive?
    @resolver_thread.alive?
  end

  def handle_resolver_done
    while !@resolver_out.empty?
      host, port, ip = @resolver_out.pop
      if tracker = find_tracker_by_host_port(host, port)
        @logger.debug("updating #{host} with ip #{ip}")
        tracker.ip = ip
      else
        @logger.error("resolved #{host} but cant find tracker")
      end
    end
  end

  def handle_resolver_retries
    @trackers.each { |tracker|
      if tracker.ip.nil? &&
          tracker.can_resolve? &&
          @resolve_in.size < RESOLVER_MAX_QUEUE_SIZE
        @logger.info("retrying resolve for " + tracker.host)
        tracker.log(EVENT_RESOLVE_ATTEMPT)
        @resolve_in.push([tracker.host, tracker.port])
      end
    }
  end

  # incoming
  def handle_incoming(ip, port, bin)
    msg = TrackerProtocolUDP.decode(bin)
    @logger.info("in: " + msg.to_s)
    case msg
    when TrackerProtocolUDP::ConnectReply
      if tracker = find_tracker_by_ip_port(ip, port)
        if query = tracker.find_last { |entry|
            entry.type == TrackerUDP::EVENT_CONNECT_QUERY &&
            entry.data[:transaction_id] == msg.transaction_id
          }
          tracker.log(TrackerUDP::EVENT_CONNECT_REPLY,
                      :transaction_id => msg.transaction_id)
          tracker.connection_id = msg.connection_id
        else
          @logger.info("received unknown connect reply for tracker " +
                       tracker.to_s)
        end
      else
        @logger.info("received unknown connect reply")
      end
    when TrackerProtocolUDP::AnnounceReply
      if tracker = find_tracker_by_ip_port(ip, port)
        if query = tracker.find_last { |entry|
            entry.type == TrackerUDP::EVENT_ANNOUNCE_QUERY &&
            entry.data[:transaction_id] == msg.transaction_id
          }
          info_hash = query.data[:info_hash]
          interval  = [msg.interval, MIN_ANNOUNCE_INTERVAL].max
          tracker.log(TrackerUDP::EVENT_ANNOUNCE_REPLY,
                      :transaction_id => msg.transaction_id,
                      :info_hash      => query.data[:info_hash],
                      :interval       => interval,
                      :event          => query.data[:event]
                      )
          puts msg.interval
          puts msg.leechers
          puts msg.seeders
          @peers[info_hash] = Set.new(msg.peers)
        end
      end
    when TrackerProtocolUDP::ScrapeReply
      @logger.info("scrape reply but we never sent a request")
    when TrackerProtocolUDP::ErrorReply
      @logger.error(msg.message)
    end
  end

  # announce
  def handle_announce
    @torrents.each { |info_hash, torrent|
      torrent.trackers.each { |t|
        tracker = find_tracker_by_host_port(t.host, t.port)
        first   = tracker.find_last { |entry|
          entry.type == TrackerUDP::EVENT_ANNOUNCE_QUERY &&
          entry.data[:info_hash] == info_hash
        }
        event = first.nil? ? 0 : 1
        if tracker.ip != nil &&
            tracker.can_announce?(info_hash, event)
          if tracker.valid_connection_id?
            handle_announce_announce(info_hash, torrent, tracker, event)
          else
            handle_announce_connect(info_hash, torrent, tracker, event)
          end
        end
      }
    }
  end

  def handle_announce_connect(info_hash, torrent, tracker, event)
    tid   = tracker.generate_transaction_id
    query = TrackerProtocolUDP::ConnectQuery.new(tid)
    @logger.debug("out: " + query.to_s)
    @socket.send(TrackerProtocolUDP.encode(query), 0,
                 tracker.ip, tracker.port)
    tracker.log(TrackerUDP::EVENT_CONNECT_QUERY,
                :transaction_id => tid,
                :info_hash      => info_hash)
  end

  def handle_announce_announce(info_hash, torrent, tracker, event)
    tid   = tracker.generate_transaction_id
    downloaded = torrent.stats.downloaded
    left = torrent.stats.left
    uploaded = torrent.stats.uploaded
    query = TrackerProtocolUDP::AnnounceQuery.new(tracker.connection_id,
                                                  tid,
                                                  info_hash,
                                                  @my_node_id,
                                                  downloaded,
                                                  left, uploaded,
                                                  event, 0,
                                                  0, -1, 12345)
    @socket.send(TrackerProtocolUDP.encode(query), 0,
                 tracker.ip, tracker.port)
    tracker.log(TrackerUDP::EVENT_ANNOUNCE_QUERY,
                :transaction_id => tid,
                :info_hash      => info_hash,
                :event          => event)
  end

  # helpers
  def find_tracker_by_host_port(host, port)
    @trackers.find { |tracker|
      tracker.host == host && tracker.port == port
    }
  end

  def find_tracker_by_ip_port(ip, port)
    @trackers.find { |tracker|
      tracker.ip == ip && tracker.port == port
    }
  end

  def find_tracker_by_transaction_id(transaction_id)
    @trackers.find { |tracker|
      tracker.has_transaction_id?(transaction_id)
    }
  end
end

class TrackerUDP
  EVENT_RESOLVE_ATTEMPT = 0
  EVENT_CONNECT_QUERY   = 1
  EVENT_CONNECT_REPLY   = 2
  EVENT_ANNOUNCE_QUERY  = 3
  EVENT_ANNOUNCE_REPLY  = 4
  EVENT_SCRAPE_QUERY    = 5
  EVENT_SCRAPE_REPLY    = 6
  EVENT_TRANSACTION_ID  = 7

  Event = Struct.new(:time, :type, :data)

  attr_accessor :ip, :connection_id
  attr_reader :host, :port

  def initialize(*a)
    @host, @port = a
    @ip          = nil
    @history     = []
  end

  def log(type, data = {})
    now = Time.now.to_i
    @history.push(Event.new(Time.now.to_i, type, data))
  end

  def can_announce?(info_hash, event)
    if last_query = find_last_query
      now = Time.now.to_i
      last_announce_reply = find_last { |entry|
        entry.type == EVENT_ANNOUNCE_REPLY &&
        entry.data[:info_hash] == info_hash
      }
      (last_query.time + backoff(count_failures) <= now) &&
        (last_announce_reply.nil? ||
         last_announce_reply.data[:event] != event ||
         last_announce_reply.time +
         last_announce_reply.data[:interval] < now)
    else
      true
    end
  end

  def can_scrape?(info_hash)
    if last_query = find_last_query
      now = Time.now.to_i
      last_scrape_reply = find_last { |entry|
        entry.type == EVENT_SCRAPE_REPLY &&
        entry.data[:info_hash] == info_hash
      }
      (last_query.time + backoff(count_failures) <= now) &&
        (last_scrape_reply.nil? ||
         last_scrape_reply.time + MIN_SCRAPE_INTERVAL <= now)
    else
      true
    end
  end

  def can_resolve?
    if entry = find_last { |entry|
        entry.type == EVENT_RESOLVE_ATTEMPT &&
        entry.time + Tracker::RESOLVER_RETRY_INTERVAL < Time.now.to_i
      }
    end
  end

  def valid_connection_id?
    find_last { |entry|
      # A client can use a connection ID until one minute after
      # it has received it. Trackers should accept the connection ID
      # until two minutes after it has been send.
      entry.type == EVENT_CONNECT_REPLY &&
      entry.time + 60 >= Time.now.to_i
      }
  end

  def generate_transaction_id
    SecureRandom.random_bytes(4).unpack("N")[0]
  end

  def has_transaction_id?(transaction_id)
    find_last { |entry|
      entry.data[:transaction_id] == transaction_id
    }
  end

  def find_last
    if i = @history.rindex { |entry|
        yield(entry)
      }
      @history[i]
    end
  end

  private
  def find_last_query
    find_last { |entry|
      entry.type == EVENT_CONNECT_QUERY ||
      entry.type == EVENT_ANNOUNCE_QUERY ||
      entry.type == EVENT_SCRAPE_QUERY
    }
  end

  def backoff(failures)
    return 0 if failures == 0
    15 * 2 ** (failures > 8 ? 8 : failures)
  end

  def count_failures
    i        = @history.length - 1
    failures = 0
    while i > 0
      case @history[i].type
      when EVENT_CONNECT_REPLY, EVENT_ANNOUNCE_REPLY then break
      when EVENT_CONNECT_QUERY, EVENT_ANNOUNCE_QUERY,
        EVENT_SCRAPE_QUERY then failures += 1
      end
      i -= 1
    end
    failures
  end
end
