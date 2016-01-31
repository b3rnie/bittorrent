
class Periodic
  def initialize(intervals = {})
    @intervals = {}
    intervals.each { |interval, callback|
      @intervals[interval] = {:callback => callback}
    }
  end

  def update(time)
    @intervals.keys.each { |interval|
      data = @intervals[interval]
      if !data.has_key?(:last) ||
          data[:last] + interval <= time
        data[:callback].call
        data[:last] = time
        @intervals[interval] = data
      end
    }
  end
end

