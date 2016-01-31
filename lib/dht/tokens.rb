#!/usr/bin/ruby
require 'securerandom'
require_relative 'periodic'

class Tokens < Periodic
  ACCEPT_TIMEOUT    = 600
  CHANGE_TIMEOUT    = 300
  PERIODIC_INTERVAL = 30

  def initialize(options = {})
    super(PERIODIC_INTERVAL)
    @logger  = options[:logger]
    @token   = create_token()
    @created = Time.now.to_i
    @tokens  = {@token => @created}
  end

  def get_token
    @token
  end

  def is_valid(token)
    @tokens.has_key?(token)
  end

  def run_periodic
    now = Time.now.to_i
    if @created + CHANGE_TIMEOUT <= now
      new_token = create_token()
      new_token_str = new_token.unpack("H*")[0]
      old_token_str = @token.unpack("H*")[0]
      @logger.debug("changing token: #{old_token_str} => #{new_token_str}")
      @token = new_token
      @created = now
      @tokens[@token] = @created
    end
    @tokens.delete_if { |token,created|
      created + ACCEPT_TIMEOUT <= now
    }
  end

  private
  def create_token()
    SecureRandom.random_bytes(10)
  end
end
