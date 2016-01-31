#!/usr/bin/ruby

class DhtException < Exception
  attr_reader :tid
  def initialize(tid)
    super
    @tid = tid
  end
end

class GenericException < DhtException
  def initialize(tid)
    super
  end
end

class ServerException < DhtException
  def initialize(tid)
    super
  end
end

class ProtocolException < DhtException
  def initialize(tid)
    super
  end
end

class MethodUnknownException < DhtException
  def initialize(tid)
    super
  end
end

class PingQuery
  attr_reader :tid, :id
  def initialize(tid, id)
    @tid = tid
    @id   = id
  end
  def to_s
    self.class.to_s + ": @id=#{id}"
  end
end

class PingReply
  attr_reader :tid, :id
  def initialize(tid, id)
    @tid = tid
    @id  = id
  end
  def to_s
    self.class.to_s + ": @id=#{id}"
  end
end

class FindNodeQuery
  attr_reader :tid, :id, :target
  def initialize(tid, id, target)
    @tid    = tid
    @id     = id
    @target = target
  end
  def to_s
    self.class.to_s + ": @id=#{id} @target=#{@target}"
  end
end

class FindNodeReply
  attr_reader :tid, :id, :nodes
  def initialize(tid, id, nodes)
    @tid   = tid
    @id    = id
    @nodes = nodes
  end
  def to_s
    self.class.to_s + ": @id=#{id} @nodes=#{@nodes.size}"
  end
end

class GetPeersQuery
  attr_reader :tid, :id, :info_hash
  def initialize(tid, id, info_hash)
    @tid       = tid
    @id        = id
    @info_hash = info_hash
  end
  def to_s
    self.class.to_s + ": @id=#{@id} @info_hash=#{@info_hash}"
  end
end

class GetPeersReply
  attr_reader :tid, :id, :token, :values, :nodes
  def initialize(tid, id, token, values, nodes)
    @tid    = tid
    @id     = id
    @token  = token
    @values = values
    @nodes  = nodes
  end
  def to_s
    values = @values.size
    nodes  = @nodes.size
    self.class.to_s + ": @id=#{@id} @values=#{values} @nodes=#{nodes}"
  end
end

class AnnouncePeerQuery
  attr_reader :tid, :id, :implied_port, :info_hash, :port, :token
  def initialize(tid, id, implied_port, info_hash, port, token)
    @tid          = tid
    @id           = id
    @implied_port = implied_port
    @info_hash    = info_hash
    @port         = port
    @token        = token
  end
  def to_s
    self.class.to_s + ": @id=#{@id} @info_hash=#{@info_hash}"
  end
end

class AnnouncePeerReply
  attr_reader :tid, :id
  def initialize(tid, id)
    @tid = tid
    @id  = id
  end
  def to_s
    self.class.to_s + ": @id=#{@id}"
  end
end

class Reply
  attr_reader :tid, :id, :nodes, :token, :values
  def initialize(tid, id, token, nodes, values)
    @tid    = tid
    @id     = id
    @token  = token
    @nodes  = nodes
    @values = values
  end
  def to_s
    self.class.to_s + ": @id=#{@id} @token=#{@token}"
  end
end

class Error
  attr_accessor :tid, :code, :description
  def initialize(tid, code, description)
    @tid         = tid
    @code        = code
    @description = description
  end
  def to_s
    self.class.to_s + ": @code=#{@code} @description=#{@description}"
  end
end

def is_query(msg)
  case msg
  when PingQuery,
       FindNodeQuery,
       GetPeersQuery,
       AnnouncePeerQuery then true
  else false
  end
end

def is_reply(msg)
  case msg
  when PingReply,
       FindNodeReply,
       GetPeersReply,
       AnnouncePeerReply then true
  else false
  end
end

def is_error(msg)
  case msg
  when Error then true
  else false
  end
end

