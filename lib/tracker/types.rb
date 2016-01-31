#!/usr/bin/ruby

class UdpProtocolException < Exception
end

class ConnectQuery
  attr_reader :protocol_id, :transaction_id
  def initialize(*a)
    @protocol_id, @transaction_id = a
  end
  def to_s
    self.class.to_s + ": @protocol_id=#{@protocol_id} @transaction_id=#{@transaction_id}"
  end
end

class ConnectReply
  attr_reader :transaction_id, :connection_id
  def initialize(*a)
    @transaction_id, @connection_id = a
  end
  def to_s
    self.class.to_s + ": @transaction_id=#{@transaction_id} @connection_id=#{@connection_id}"
  end
end

class AnnounceQuery
  attr_reader :connection_id, :transaction_id, :info_hash, :peer_id, :downloaded, :left, :uploaded
  attr_reader :event, :ip, :key, :num_want, :port
  def initialize(*a)
    @connection_id, @transaction_id, @info_hash, @peer_id, @downloaded, @left, @uploaded,
    @event, @ip, @key, @num_want, @port = a
  end

  def to_s
    self.class.to_s + ": @transaction_id=#{@transaction_id} @connection_id=#{@connection_id} " +
      "@info_hash=#{@info_hash} @peer_id=#{@peer_id} @downloaded=#{@downloaded} @left=#{@left} " +
      "@uploaded=#{@uploaded} @event=#{@event} @ip=#{@ip} @key=#{@key} " +
      "@num_want=#{@num_want} @port=#{@port}"
  end
end

class AnnounceReply
  attr_reader :transaction_id, :interval, :leechers, :seeders, :peers
  def initialize(*a)
    @transaction_id, @interval, @leechers, @seeders, @peers = a
  end

  def to_s
    self.class.to_s + ": @transaction_id=#{@transaction_id} @interval=#{@interval} " +
      "@leechers=#{@leechers} @seeders=#{@seeders} @peers=#{@peers}"
  end
end

class ScrapeQuery
  attr_reader :connection_id, :transaction_id, :info_hashes
  def initialize(*a)
    @connection_id, @transaction_id, @info_hashes = a
  end

  def to_s
    self.class.to_s + ": @connection_id=#{@connection_id} @transaction_id=#{@transaction_id} " +
      "@info_hashes=#{@info_hashes}"
  end
end

class ScrapeReply
  attr_reader :connection_id, :info
  def initialize(*a)
    @connection_id, @info = a
  end
end

class ErrorReply
  attr_reader :transaction_id, :message
  def initialize(*a)
    @transaction_id, @message = a
  end

  def to_s
    self.class.to_s + ": @transaction_id=#{@transaction_id} @message=#{@message}"
  end
end

