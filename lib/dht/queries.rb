#!/usr/bin/ruby
require_relative 'periodic'

class Queries < Periodic
  REQUEST_TIMEOUT   = 120
  PERIODIC_INTERVAL = 30

  def initialize(options = {})
    super(PERIODIC_INTERVAL)
    @logger   = options[:logger]
    @queries  = {}
    @next_tid = 0
  end

  def with_tid
    tid = [@next_tid].pack("n")
    @next_tid = @next_tid >= 0xFFFF ? 0 : @next_tid + 1
    query = yield(tid)
    @queries[tid] = [Time.now.to_i, query]
    query
  end

  def get_query(tid)
    if (query = @queries[tid])
      query[1]
    end
  end

  def run_periodic
    now = Time.now.to_i
    @queries.delete_if { |tid,value|
      value[0] + REQUEST_TIMEOUT <= now
    }
  end
end
