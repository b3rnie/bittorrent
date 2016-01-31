class Block
  attr_reader :piece, :start, :length

  def initialize(*a)
    @piece, @start, @length = a
  end

  def ==(o)
    o.instance_of?(self.class) &&
      @piece == o.piece && @start == o.start && @length == o.length
  end

  def eql?(o)
    self == o
  end

  def hash
    [@piece, @start, @length].hash
  end
end
