# frozen_string_literal: true

require 'chunky_png'
require_relative 'lzw_compressor'
require_relative 'palette'

module Btape
  # A deliberately small GIF89a encoder, so that recording needs no native
  # image or video dependency.
  class GifEncoder
    # A GIF frame delay is two bytes of hundredths of a second.
    MAX_DELAY = 0xffff
    # Eight bits per pixel: one index into a 256-colour table.
    MIN_CODE_SIZE = "\x08"

    def self.for(settings)
      new(
        delay: (settings.frame_delay * 100).round,
        loop_count: settings.loop_count,
        quantizer: settings.quantizer,
        scale: settings.scale,
        width: settings.output_width
      )
    end

    def initialize(delay: 10, loop_count: 0, quantizer: :adaptive, scale: 1.0, width: nil, dedupe: true)
      @delay = delay.clamp(1, MAX_DELAY)
      @loop_count = loop_count
      @quantizer = quantizer
      @scale = scale
      @width = width
      @dedupe = dedupe
      @compressor = LzwCompressor.new
    end

    # Returns the GIF as a binary String. Frames are PNG paths or ChunkyPNG
    # canvases. Callers that are not writing to the filesystem — attaching the
    # GIF to a record, say — want this rather than a file to read back.
    def encode(frames)
      raise Error, 'no screenshots were captured' if frames.empty?

      images = frames.map { |frame| resize(image(frame)) }
      width, height = images.first.dimension.to_a
      raise Error, 'captured screenshots have different dimensions' unless images.all? do |image|
        image.dimension.to_a == [width, height]
      end

      palette = Palette.build(@quantizer, images)
      gif(collapse(images.map { |image| index(image, palette) }), width, height, palette)
    end

    # Writes to a path, or to anything that responds to write.
    def write(frames, output)
      data = encode(frames)
      return output.write(data) if output.respond_to?(:write)

      File.binwrite(output, data)
    end

    private

    def image(frame)
      frame.is_a?(ChunkyPNG::Canvas) ? frame : ChunkyPNG::Image.from_file(frame)
    end

    def resize(image)
      target = @width || (image.width * @scale).round
      return image if target == image.width || target < 1

      # A wide enough source rounds its scaled height down to nothing, and a
      # zero-height canvas becomes a GIF no decoder can show.
      height = [(image.height * target.to_f / image.width).round, 1].max
      image.resample_bilinear(target, height)
    end

    def index(image, palette)
      image.pixels.map { |pixel| palette.index_for(pixel) }
    end

    # A run that sits on one page for a second is a dozen identical frames.
    # Holding the first for longer says the same thing in a fraction of the
    # bytes, and spares a decoder the redundant frames.
    def collapse(frames)
      frames.each_with_object([]) do |pixels, collapsed|
        previous = collapsed.last
        if @dedupe && previous && previous.first == pixels
          previous[1] = [previous[1] + @delay, MAX_DELAY].min
        else
          collapsed << [pixels, @delay]
        end
      end
    end

    def gif(frames, width, height, palette)
      data = +'GIF89a'.b
      data << [width, height, 0b11110111, 0, 0].pack('vvCCC') << palette.to_gct
      data << netscape
      frames.each { |pixels, delay| write_frame(data, pixels, delay, width, height) }
      data << ';'.b
    end

    # The application extension that carries the loop count. Zero loops
    # forever, which is what an unattended recording usually wants.
    def netscape
      +"!\xFF\x0BNETSCAPE2.0\x03\x01".b << [@loop_count].pack('v') << "\x00".b
    end

    def write_frame(data, pixels, delay, width, height)
      data << "!\xF9\x04\x00".b << [delay].pack('v') << "\x00\x00".b
      data << ','.b << [0, 0, width, height, 0].pack('vvvvC')
      data << MIN_CODE_SIZE.b
      lzw(pixels).bytes.each_slice(255) { |slice| data << slice.length.chr << slice.pack('C*') }
      data << "\x00".b
    end

    def lzw(pixels)
      codes = []
      @compressor.call(pixels) { |code, width| codes << [code, width] }
      pack_codes(codes)
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
