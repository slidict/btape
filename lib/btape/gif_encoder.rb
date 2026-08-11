# frozen_string_literal: true

require 'chunky_png'

module Btape
  # A deliberately small GIF89a encoder. RGB332 gives a fixed 256-colour palette,
  # avoiding a native image or video dependency.
  class GifEncoder
    def initialize(delay: 10)
      @delay = delay
    end

    def write(png_paths, output)
      raise Error, 'no screenshots were captured' if png_paths.empty?

      images = png_paths.map { |path| ChunkyPNG::Image.from_file(path) }
      width, height = images.first.dimension.to_a
      raise Error, 'captured screenshots have different dimensions' unless images.all? do |image|
        image.dimension.to_a == [width, height]
      end

      File.binwrite(output, gif(images, width, height))
    end

    CLEAR_CODE = 256
    FINISH_CODE = 257
    MAX_CODE_WIDTH = 12
    MAX_DICTIONARY_SIZE = 1 << MAX_CODE_WIDTH

    private

    def gif(images, width, height)
      data = +'GIF89a'.b
      data << [width, height, 0b11110111, 0, 0].pack('vvCCC') << palette
      data << "!\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00".b
      images.each { |image| write_frame(data, image, width, height) }
      data << ';'.b
    end

    def write_frame(data, image, width, height)
      data << "!\xF9\x04\x00".b << [@delay].pack('v') << "\x00\x00".b
      data << ','.b << [0, 0, width, height, 0].pack('vvvvC')
      compressed = lzw(image)
      data << "\x08".b
      compressed.bytes.each_slice(255) { |slice| data << slice.length.chr << slice.pack('C*') }
      data << "\x00".b
    end

    def palette
      (0..255).map { |i| [((i >> 5) & 7) * 255 / 7, ((i >> 2) & 7) * 255 / 7, (i & 3) * 255 / 3].pack('C3') }.join.b
    end

    def lzw(image)
      pixels = image.pixels.map { |pixel| rgb332(pixel) }
      codes = []
      emit = ->(code, width) { codes << [code, width] }
      emit.call(CLEAR_CODE, 9)

      if pixels.empty?
        emit.call(FINISH_CODE, 9)
        return pack_codes(codes)
      end

      compress(pixels, emit)
      pack_codes(codes)
    end

    def compress(pixels, emit)
      dictionary = root_dictionary
      next_code = FINISH_CODE + 1
      code_width = 9
      current_code = pixels.first

      pixels.drop(1).each do |pixel|
        key = (current_code << 8) | pixel
        if dictionary.key?(key)
          current_code = dictionary[key]
          next
        end

        emit.call(current_code, code_width)
        dictionary, next_code, code_width = advance(dictionary, key, next_code, code_width, emit)
        current_code = pixel
      end

      emit.call(current_code, code_width)
      emit.call(FINISH_CODE, code_width)
    end

    def advance(dictionary, key, next_code, code_width, emit)
      if next_code == MAX_DICTIONARY_SIZE
        emit.call(CLEAR_CODE, code_width)
        return [root_dictionary, FINISH_CODE + 1, 9]
      end

      dictionary[key] = next_code
      next_code += 1
      code_width += 1 if next_code > (1 << code_width) - 1 && code_width < MAX_CODE_WIDTH
      [dictionary, next_code, code_width]
    end

    def root_dictionary
      (0..255).to_h { |value| [value, value] }
    end

    def rgb332(pixel)
      (ChunkyPNG::Color.r(pixel) & 0xe0) | ((ChunkyPNG::Color.g(pixel) & 0xe0) >> 3) | (ChunkyPNG::Color.b(pixel) >> 6)
    end

    def pack_codes(codes)
      buffer = 0
      count = 0
      output = +''.b
      codes.each do |code, bits|
        buffer |= code << count
        count += bits
        while count >= 8
          output << (buffer & 0xff).chr
          buffer >>= 8
          count -= 8
        end
      end
      output << (buffer & 0xff).chr if count.positive?
      output
    end
  end
end
