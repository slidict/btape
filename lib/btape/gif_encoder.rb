require "chunky_png"

module Btape
  # A deliberately small GIF89a encoder. RGB332 gives a fixed 256-colour palette,
  # avoiding a native image or video dependency.
  class GifEncoder
    def initialize(delay: 10)
      @delay = delay
    end

    def write(png_paths, output)
      raise Error, "no screenshots were captured" if png_paths.empty?

      images = png_paths.map { |path| ChunkyPNG::Image.from_file(path) }
      width, height = images.first.dimension
      raise Error, "captured screenshots have different dimensions" unless images.all? { |image| image.dimension == [width, height] }

      File.binwrite(output, gif(images, width, height))
    end

    private

    def gif(images, width, height)
      data = +"GIF89a".b
      data << [width, height, 0b11110111, 0, 0].pack("vvCCC") << palette
      data << "!\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00".b
      images.each do |image|
        data << "!\xF9\x04\x00".b << [@delay].pack("v") << "\x00\x00".b
        data << ",".b << [0, 0, width, height, 0].pack("vvvvC")
        compressed = lzw(image)
        data << "\x08".b
        compressed.bytes.each_slice(255) { |slice| data << slice.length.chr << slice.pack("C*") }
        data << "\x00".b
      end
      data << ";".b
    end

    def palette
      (0..255).map { |i| [((i >> 5) & 7) * 255 / 7, ((i >> 2) & 7) * 255 / 7, (i & 3) * 255 / 3].pack("C3") }.join.b
    end

    def lzw(image)
      clear = 256
      finish = 257
      codes = []
      # Clearing between pixels is less compact, but keeps the code width fixed
      # and makes this tiny encoder predictable for an MVP.
      image.pixels.each do |pixel|
        codes << clear << rgb332(pixel)
      end
      codes << finish
      pack_codes(codes, 9)
    end

    def rgb332(pixel)
      (ChunkyPNG::Color.r(pixel) & 0xe0) | ((ChunkyPNG::Color.g(pixel) & 0xe0) >> 3) | (ChunkyPNG::Color.b(pixel) >> 6)
    end

    def pack_codes(codes, bits)
      buffer = 0
      count = 0
      output = +"".b
      codes.each do |code|
        buffer |= code << count
        count += bits
        while count >= 8
          output << (buffer & 0xff).chr
          buffer >>= 8
          count -= 8
        end
      end
      output << buffer.chr if count.positive?
      output
    end
  end
end

