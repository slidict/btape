# frozen_string_literal: true

require_relative 'spec_helper'
require 'stringio'
require 'tmpdir'

# A minimal, standards-compliant GIF89a + variable-width LZW decoder, used
# only to verify that GifEncoder's output round-trips correctly. It is
# intentionally independent of GifEncoder's own implementation.
module GifDecoder
  State = Struct.new(:dictionary, :next_code, :code_width, :prev)

  module_function

  def decode_first_frame(data)
    width, height, pos = read_screen_descriptor(data)
    pos = skip_to_image_descriptor(data, pos)
    pos = skip_image_descriptor(pos)
    min_code_size = data.getbyte(pos)
    pos += 1
    compressed = read_sub_blocks(data, pos)

    pixels = decode_lzw(compressed, min_code_size)
    { width: width, height: height, pixels: pixels }
  end

  def read_screen_descriptor(data)
    width, height, packed = data[6, 5].unpack('vvC')
    gct_size = 2 << (packed & 0x7)
    pos = 13
    pos += gct_size * 3 if packed.anybits?(0x80)
    [width, height, pos]
  end

  def skip_to_image_descriptor(data, pos)
    loop do
      case data.getbyte(pos)
      when 0x21 # extension block
        pos += 2
        loop do
          block_size = data.getbyte(pos)
          pos += 1
          break if block_size.zero?

          pos += block_size
        end
      when 0x2C # image descriptor
        return pos
      else
        raise "unexpected byte at #{pos}"
      end
    end
  end

  def skip_image_descriptor(pos)
    pos + 10
  end

  def read_sub_blocks(data, pos)
    bytes = +''.b
    loop do
      block_size = data.getbyte(pos)
      pos += 1
      break if block_size.zero?

      bytes << data[pos, block_size]
      pos += block_size
    end
    bytes
  end

  def decode_lzw(bytes, min_code_size)
    clear_code = 1 << min_code_size
    end_code = clear_code + 1
    reader = BitReader.new(bytes)
    state = reset_state(clear_code, end_code)
    output = []

    loop do
      code = reader.read(state.code_width)
      if code == clear_code
        state = reset_state(clear_code, end_code)
      elsif code == end_code
        break
      else
        output.concat(decode_code(state, code, output.length))
      end
    end

    output
  end

  def reset_state(clear_code, end_code)
    dictionary = (0...clear_code).to_h { |i| [i, [i]] }
    State.new(dictionary, end_code + 1, Math.log2(clear_code).to_i + 1, nil)
  end

  def decode_code(state, code, output_length)
    entry = lookup_entry(state, code, output_length)
    if state.prev && state.next_code < 4096
      state.dictionary[state.next_code] = state.dictionary[state.prev] + [entry.first]
      state.next_code += 1
      state.code_width += 1 if state.next_code > (1 << state.code_width) - 1 && state.code_width < 12
    end
    state.prev = code
    entry
  end

  def lookup_entry(state, code, output_length)
    if state.dictionary.key?(code)
      state.dictionary[code]
    elsif code == state.next_code && state.prev
      state.dictionary[state.prev] + [state.dictionary[state.prev].first]
    else
      raise "invalid code #{code} at output length #{output_length}"
    end
  end

  # LSB-first bit reader, matching GIF's packed sub-block byte order.
  class BitReader
    def initialize(bytes)
      @bytes = bytes
      @buffer = 0
      @count = 0
      @pos = 0
    end

    def read(width)
      while @count < width
        @buffer |= @bytes.getbyte(@pos) << @count
        @count += 8
        @pos += 1
      end
      value = @buffer & ((1 << width) - 1)
      @buffer >>= width
      @count -= width
      value
    end
  end
end

RSpec.describe Btape::GifEncoder do
  it 'writes an animated gif without an external process' do
    Dir.mktmpdir do |directory|
      frames = %w[red blue].map.with_index do |colour, index|
        path = File.join(directory, "#{index}.png")
        ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color(colour)).save(path)
        path
      end
      output = File.join(directory, 'result.gif')

      described_class.new.write(frames, output)

      data = File.binread(output)
      expect(data).to start_with('GIF89a')
      expect(data.scan("\x21\xF9\x04".b).length).to eq(2)
      expect(data).to end_with(';')
    end
  end

  it 'returns the gif as a binary string' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'frame.png')
      ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red')).save(path)

      data = described_class.new.encode([path])

      expect(data).to start_with('GIF89a')
      expect(data.encoding).to eq(Encoding::BINARY)
    end
  end

  it 'encodes images it is handed directly, without a file to read back' do
    data = described_class.new.encode([ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))])

    expect(data).to start_with('GIF89a')
  end

  it 'writes into anything that responds to write' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'frame.png')
      ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red')).save(path)
      buffer = StringIO.new(+''.b)

      described_class.new.write([path], buffer)

      expect(buffer.string).to start_with('GIF89a')
    end
  end

  it 'refuses to encode without any frames' do
    expect { described_class.new.encode([]) }
      .to raise_error(Btape::Error, 'no screenshots were captured')
  end

  it 'round-trips pixel data correctly across an LZW code-width boundary' do
    # A single solid colour, wide/tall enough that the dictionary must grow
    # past 511 entries, forcing the encoder's 9-to-10-bit code width switch.
    # A previous version of the encoder decoded incorrectly a few hundred
    # codes after crossing exactly this kind of boundary.
    Dir.mktmpdir do |directory|
      width = 100
      height = 400
      path = File.join(directory, 'frame.png')
      ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(30, 144, 255)).save(path)
      output = File.join(directory, 'result.gif')

      described_class.new.write([path], output)

      decoded = GifDecoder.decode_first_frame(File.binread(output))
      expect(decoded[:width]).to eq(width)
      expect(decoded[:height]).to eq(height)
      expect(decoded[:pixels].length).to eq(width * height)
      expect(decoded[:pixels].uniq.length).to eq(1)
    end
  end
end
