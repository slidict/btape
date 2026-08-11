require_relative "test_helper"
require "tmpdir"

class GifEncoderTest < Minitest::Test
  def test_writes_an_animated_gif_without_an_external_process
    Dir.mktmpdir do |directory|
      frames = %w[red blue].map.with_index do |colour, index|
        path = File.join(directory, "#{index}.png")
        ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color(colour)).save(path)
        path
      end
      output = File.join(directory, "result.gif")

      Btape::GifEncoder.new.write(frames, output)

      data = File.binread(output)
      assert data.start_with?("GIF89a")
      assert_equal 2, data.scan("\x21\xF9\x04".b).length
      assert data.end_with?(";")
    end
  end
end

