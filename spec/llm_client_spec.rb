# frozen_string_literal: true

require_relative 'spec_helper'
require 'json'
require 'socket'

RSpec.describe Btape::LLM::Client do
  # Anyone working on this feature has these exported, and half of what is
  # below is about what the client does when nobody has said.
  around do |example|
    with_environment('BTAPE_LLM_URL' => nil, 'BTAPE_LLM_MODEL' => nil, 'BTAPE_LLM_KEY' => nil) { example.run }
  end

  # A server rather than a stubbed Net::HTTP: what is being checked is that
  # btape speaks the protocol an LM Studio or an Ollama answers, and a stub
  # would only agree with whatever this file assumed about it.
  #
  # It answers one request and stops, and returns that request, so each
  # example says what it is answering and nothing lingers between them.
  def with_server(status: '200 OK', body: '{}')
    server = TCPServer.new('127.0.0.1', 0)
    request = nil
    thread = Thread.new { request = serve(server, status, body) }
    yield("http://127.0.0.1:#{server.addr[1]}/v1")
    thread.join(2)
    request
  ensure
    thread&.kill
    server&.close
  end

  def serve(server, status, body)
    socket = server.accept
    request = read_request(socket)
    socket.print("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    socket.close
    request
  end

  def read_request(socket)
    head = +''
    while (line = socket.gets)
      head << line
      break if line == "\r\n"
    end
    length = head[/^content-length:\s*(\d+)/i, 1].to_i
    { line: head.lines.first.strip, head: head, body: length.positive? ? socket.read(length) : '' }
  end

  def completion(content)
    JSON.generate(choices: [{ message: { role: 'assistant', content: content } }])
  end

  def with_environment(values)
    previous = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it 'asks for a completion and returns what the model said' do
    request = with_server(body: completion("Output demo.gif\n")) do |url|
      client = described_class.new(base_url: url, model: 'local-model')

      expect(client.complete([{ role: 'user', content: 'hello' }])).to eq("Output demo.gif\n")
    end

    expect(request[:line]).to eq('POST /v1/chat/completions HTTP/1.1')
    expect(JSON.parse(request[:body])).to include('model' => 'local-model', 'stream' => false)
  end

  it 'sends a key when one was given' do
    request = with_server(body: completion('x')) do |url|
      described_class.new(base_url: url, model: 'm', api_key: 'secret').complete([])
    end

    expect(request[:head]).to include('Bearer secret')
  end

  # A model running on this machine usually has no key, and sending an empty
  # one is a way to be turned away by a server that checks.
  it 'sends none when it was not given one' do
    request = with_server(body: completion('x')) do |url|
      described_class.new(base_url: url, model: 'm').complete([])
    end

    expect(request[:head].downcase).not_to include('authorization')
  end

  # Nobody remembers the name a downloaded model was given, and both LM
  # Studio and Ollama will say when asked.
  it 'asks the server which model is loaded when it was not told' do
    request = with_server(body: JSON.generate(data: [{ id: 'qwen2.5-coder-7b' }])) do |url|
      expect(described_class.new(base_url: url).model).to eq('qwen2.5-coder-7b')
    end

    expect(request[:line]).to eq('GET /v1/models HTTP/1.1')
  end

  it 'says so when no model is loaded' do
    with_server(body: JSON.generate(data: [])) do |url|
      expect { described_class.new(base_url: url).model }
        .to raise_error(Btape::LLM::Error, /no model is loaded/)
    end
  end

  it 'reports what the server complained about, not the status alone' do
    error = JSON.generate(error: { message: 'context length exceeded' })

    with_server(status: '400 Bad Request', body: error) do |url|
      expect { described_class.new(base_url: url, model: 'm').complete([]) }
        .to raise_error(Btape::LLM::Error, /400.*context length exceeded/)
    end
  end

  it 'reports an answer that is not JSON' do
    with_server(body: '<html>nope</html>') do |url|
      expect { described_class.new(base_url: url, model: 'm').complete([]) }
        .to raise_error(Btape::LLM::Error, /not JSON/)
    end
  end

  it 'reports a reply carrying no message' do
    with_server(body: JSON.generate(choices: [])) do |url|
      expect { described_class.new(base_url: url, model: 'm').complete([]) }
        .to raise_error(Btape::LLM::Error, /without a message/)
    end
  end

  # Some servers answer with the content as a list of parts rather than as
  # text, which is this client's to report rather than to trip over.
  it 'reports a message that is not text' do
    parts = JSON.generate(choices: [{ message: { content: [{ type: 'text', text: 'Output demo.gif' }] } }])

    with_server(body: parts) do |url|
      expect { described_class.new(base_url: url, model: 'm').complete([]) }
        .to raise_error(Btape::LLM::Error, /without a message/)
    end
  end

  it 'reports a model list in a shape it does not recognise' do
    with_server(body: JSON.generate(data: ['qwen2.5-coder-7b'])) do |url|
      expect { described_class.new(base_url: url).model }
        .to raise_error(Btape::LLM::Error, /no model is loaded/)
    end
  end

  it 'reports a connection dropped before the answer arrived' do
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new { server.accept.close }
    url = "http://127.0.0.1:#{server.addr[1]}/v1"

    expect { described_class.new(base_url: url, model: 'm').complete([]) }
      .to raise_error(Btape::LLM::Error, /closed the connection before answering/)
    thread.join(2)
  ensure
    thread&.kill
    server&.close
  end

  # The likeliest failure by far: the server was never started.
  it 'names the address when nothing is listening there' do
    port = TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] }
    url = "http://127.0.0.1:#{port}/v1"

    expect { described_class.new(base_url: url, model: 'm').complete([]) }
      .to raise_error(Btape::LLM::Error, /could not reach a model server at #{Regexp.escape(url)}/)
  end

  it 'takes its defaults from the environment' do
    with_environment('BTAPE_LLM_URL' => 'http://localhost:11434/v1', 'BTAPE_LLM_MODEL' => 'llama3') do
      client = described_class.new

      expect(client.base_url).to eq('http://localhost:11434/v1')
      expect(client.model).to eq('llama3')
    end
  end
end
