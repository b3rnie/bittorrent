#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'securerandom'

class ConnectionIds
  ACCEPT_TIMEOUT = 120

  def initialize(options = {})
    @logger = options[:logger]
    @connection_ids = {}
  end

  def is_valid(connection_id)
    if timestamp = @connection_ids[connection_id]
      timestamp + ACCEPT_TIMEOUT > Time.now.to_i
    end
  end

  def with_connection_id
    bytes = SecureRandom.random_bytes(8).unpack("NN")
    connection_id = bytes[0] << 32
    connection_id |= bytes[1]
    @connection_ids[connection_id] = Time.now.to_i
    yield(connection_id)
  end

  def garbage_collect()
    now = Time.now.to_i
    @connection_ids.delete_if { |connection_id, created|
      created + ACCEPT_TIMEOUT <= now
    }
  end
end
