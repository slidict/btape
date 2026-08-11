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

  # The delay lives in the two bytes after each graphic control block's
  # introducer, block size and packed field.
  def frame_delays(data)
    offsets = []
    position = 0
    while (offset = data.index("\x21\xF9\x04".b, position))
      offsets << offset
      position = offset + 1
    end
    offsets.map { |offset| data[offset + 4, 2].unpack1('v') }
  end

  describe 'frame delays' do
    it 'writes the delay it was given' do
      data = described_class.new(delay: 25).encode([ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))])

      expect(frame_delays(data)).to eq([25])
    end

    # A run that sits on one page is a dozen identical frames; holding the
    # first for longer says the same thing in a fraction of the bytes.
    it 'collapses identical consecutive frames into a longer delay' do
      red = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))
      blue = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('blue'))

      data = described_class.new(delay: 10).encode([red, red, red, blue])

      expect(frame_delays(data)).to eq([30, 10])
    end

    it 'keeps every frame when dedupe is off' do
      red = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))

      data = described_class.new(delay: 10, dedupe: false).encode([red, red, red])

      expect(frame_delays(data)).to eq([10, 10, 10])
    end

    it 'only collapses frames that are next to each other' do
      red = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))
      blue = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('blue'))

      data = described_class.new(delay: 10).encode([red, blue, red])

      expect(frame_delays(data)).to eq([10, 10, 10])
    end
  end

  it 'writes the loop count into the netscape extension' do
    data = described_class.new(loop_count: 3).encode([ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))])

    expect(data).to include("NETSCAPE2.0\x03\x01\x03\x00".b)
  end

  describe 'resizing' do
    it 'scales the frames down' do
      data = described_class.new(scale: 0.5).encode([ChunkyPNG::Image.new(40, 20, ChunkyPNG::Color('red'))])

      expect(data[6, 4].unpack('vv')).to eq([20, 10])
    end

    it 'takes an explicit width and keeps the aspect ratio' do
      data = described_class.new(width: 10).encode([ChunkyPNG::Image.new(40, 20, ChunkyPNG::Color('red'))])

      expect(data[6, 4].unpack('vv')).to eq([10, 5])
    end

    it 'keeps a row of height when the aspect ratio would round it away' do
      data = described_class.new(width: 10).encode([ChunkyPNG::Image.new(400, 3, ChunkyPNG::Color('red'))])

      expect(data[6, 4].unpack('vv')).to eq([10, 1])
    end

    it 'leaves the frames alone at the default scale' do
      data = described_class.new.encode([ChunkyPNG::Image.new(40, 20, ChunkyPNG::Color('red'))])

      expect(data[6, 4].unpack('vv')).to eq([40, 20])
    end
  end

  it 'builds itself from settings' do
    encoder = described_class.for(Btape::Settings.new(frame_delay: 0.25, loop_count: 2))

    expect(frame_delays(encoder.encode([ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color('red'))]))).to eq([25])
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
