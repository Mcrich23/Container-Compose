// container-compose.rb
class Container-Compose < Formula
  desc "Manage the local dictionary on Mac."
  homepage "https://github.com/Mcrich23/Container-Compose"
  url "https://github.com/Mcrich23/Container-Compose.git", tag: "0.1.0"
  version "0.1.0"

  depends_on "xcode": [:build]

  def install
    system "make", "install", "prefix=#{prefix}"
  end

  test do
    system "#{bin}container-compose", "list"
  end
end


