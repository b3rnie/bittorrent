require 'ipaddr'
require_relative '../utils/conversions'

module TrackerProtocolUDP
  class ProtocolException < Exception; end

  class ConnectQuery
    attr_reader :transaction_id
    def initialize(transaction_id)
      @transaction_id = transaction_id
    end
    def to_s
      self.class.to_s + ": @transaction_id=#{transaction_id}"
    end
  end

  class ConnectReply
    attr_reader :transaction_id, :connection_id
    def initialize(*a)
      @transaction_id, @connection_id = a
    end
    def to_s
      self.class.to_s + ": @transaction_id=#{transaction_id} " +
        "@connection_id=#{connection_id}"
    end
  end

  class AnnounceQuery
    attr_reader :connection_id, :transaction_id
    attr_reader :info_hash, :peer_id, :downloaded, :left, :uploaded
    attr_reader :event, :ip, :key, :num_want, :port
    def initialize(*a)
      @connection_id, @transaction_id, @info_hash, @peer_id,
      @downloaded, @left, @uploaded, @event, @ip, @key,
      @num_want, @port = a

      @event ||= 0
      @ip ||= 0
      @num_want ||= -1
    end

    def to_s
      self.class.to_s + ": @transaction_id=#{transaction_id} " +
        "@connection_id=#{connection_id} @info_hash=#{info_hash} " +
        "@peer_id=#{peer_id} @downloaded=#{downloaded} @left=#{left} " +
        "@uploaded=#{uploaded} @event=#{event} @ip=#{ip} @key=#{key} " +
        "@num_want=#{num_want} @port=#{port}"
    end
  end

  class AnnounceReply
    attr_reader :transaction_id, :interval, :leechers, :seeders
    attr_reader :peers
    def initialize(*a)
      @transaction_id, @interval, @leechers, @seeders, @peers = a
    end

    def to_s
      self.class.to_s + ": @transaction_id=#{transaction_id} " +
        "@interval=#{interval} @leechers=#{leechers} " +
        "@seeders=#{seeders}"
    end
  end

  class ScrapeQuery
    attr_reader :connection_id, :transaction_id, :info_hash
    def initialize(*a)
      @connection_id, @transaction_id, @info_hash = a
    end
  end

  class ScrapeReply

  end

  class ErrorReply
    attr_reader :transaction_id, :message
    def initialize(*a)
      @transaction_id, @message = a
    end

    def to_s
      self.class.to_s + ": @transaction_id=#{transaction_id} " +
        "@message=#{message}"
    end
  end

  def TrackerProtocolUDP.encode(msg)
    case msg
    when ConnectQuery
      [0x41727101980 >> 32,
       0x41727101980 & 0xFFFFFFFF,
       0,
       msg.transaction_id].pack("NNNN")
    when AnnounceQuery
      [msg.connection_id >> 32,
       msg.connection_id & 0xFFFFFFFF,
       1,
       msg.transaction_id].pack("NNNN") +
        # 20 bytes
        Conversions.hex_id_to_binary(msg.info_hash) +
        # 20 bytes
        Conversions.hex_id_to_binary(msg.peer_id) +
        [(msg.downloaded >> 32) & 0xFFFFFFFF,
         msg.downloaded & 0xFFFFFFFF,
         (msg.left >> 32) & 0xFFFFFFFF,
         msg.left & 0xFFFFFFFF,
         (msg.uploaded >> 32) & 0xFFFFFFFF,
         msg.uploaded & 0xFFFFFFFF].pack("NNNNNN") +
        [msg.event,
         msg.ip,
         msg.key,
         msg.num_want,
         msg.port].pack("NNNNn")
    when Scrape
    end
  end

  def TrackerProtocolUDP.decode(data)
    case data[0,4].unpack("N")[0]
    when 0
      return nil if data.length != 16
      transaction_id = data[4,4].unpack("N")[0]
      connection_id  = data[8,4].unpack("N")[0] << 32
      connection_id |= data[12,4].unpack("N")[0]
      ConnectReply.new(transaction_id, connection_id)
    when 1
      return nil if data.length < 20
      return nil if ((data.length - 20) % 6) != 0
      transaction_id = data[4,4].unpack("N")[0]
      interval = data[8,4].unpack("N")[0]
      leechers = data[12,4].unpack("N")[0]
      seeders  = data[16,4].unpack("N")[0]
      peers    = data[20..-1].chars.each_slice(6).map(&:join).map { |s|
        [IPAddr.new(s[0,4].unpack("N")[0], Socket::AF_INET),
         s[4,2].unpack("n")[0]]
      }
      AnnounceReply.new(transaction_id, interval, leechers, seeders,
                        peers)
    when 2
      ScrapeReply.new
    when 3
      return nil if data.length < 4
      transaction_id = data[4,4].unpack("N")[0]
      message        = data[8,-1]
      ErrorReply.new(transaction_id, message)
    end
  end
end
