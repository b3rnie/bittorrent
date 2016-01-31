class Periodic
  def initialize(interval)
    @periodic_last     = nil
    @periodic_interval = interval
  end

  def periodic
    now = Time.now.to_i
    if @periodic_last.nil? ||
       @periodic_last + @periodic_interval <= now
      @periodic_last = now
      run_periodic
    end
  end
end
