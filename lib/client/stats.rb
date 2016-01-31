
class Stats
  attr_reader :left, :uploaded, :downloaded
  def initialize(left)
    @left       = left
    @uploaded   = 0
    @downloaded = 0
  end

  def register_uploaded(uploaded)
    @uploaded += uploaded
  end

  def reqister_downloaded(downloaded)
    @downloaded += downloaded
    @left       -= downloaded
    # TODO: assert left not negative
  end
end
