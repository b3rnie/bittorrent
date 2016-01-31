class Rate
  def initialize
    @upload   = []
    @download = []
  end

  def register_download(length)
    register(@download, length)
  end

  def register_upload(length)
    register(@upload, length)
  end

  # per second
  def upload
    calculate_rate(@upload)
  end

  def download
    calculate_rate(@download)
  end

  private
  def register(bucket, length)
    bucket.push([Time.now.to_f, length])
    bucket = bucket.last(10)
  end

  def calculate_rate(bucket)
    return 0 if bucket.empty?
    duration = Time.now.to_f - bucket.first[0]
    length   = bucket.inject(0) { |acc,data| acc + data[1] }
    return 0 if duration <= 0
    length / duration
  end
end
