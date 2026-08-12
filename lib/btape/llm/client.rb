# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative '../error'

module Btape
  # Talking to a language model, which btape does for one purpose: writing a
  # tape from a description of the recording someone wants.
  module LLM
    # Raised when the model, or the server in front of it, could not answer.
    class Error < Btape::Error; end

    # A chat client for an OpenAI-compatible server. Nothing here knows which
    # one it is talking to: LM Studio, Ollama, llama.cpp's server and vLLM all
    # answer `/v1/chat/completions` in the same shape, so pointing `--llm-url`
    # at one of them is the whole of the configuration.
    #
    # The defaults assume the model is running on this machine, where there is
    # usually no key to send and no reason for the request to leave it.
    class Client
      # LM Studio's; Ollama serves the same API on 11434.
      DEFAULT_BASE_URL = 'http://localhost:1234/v1'
      DEFAULT_TEMPERATURE = 0.2
      # A local model on a CPU answers in tens of seconds rather than the
      # hundreds of milliseconds a hosted one would take.
      DEFAULT_TIMEOUT = 300

      # How much of a server's error body to quote back. Enough to name the
      # problem, not so much that a stack trace fills the terminal.
      ERROR_BODY_LIMIT = 500

      attr_reader :base_url

      def initialize(base_url: nil, model: nil, api_key: nil, temperature: nil, timeout: nil)
        @base_url = (base_url || ENV.fetch('BTAPE_LLM_URL', DEFAULT_BASE_URL)).chomp('/')
        @model = model || ENV.fetch('BTAPE_LLM_MODEL', nil)
        @api_key = api_key || ENV.fetch('BTAPE_LLM_KEY', nil)
        @temperature = temperature || DEFAULT_TEMPERATURE
        @timeout = timeout || DEFAULT_TIMEOUT
      end

      # Sends the conversation and returns the reply's text.
      def complete(messages)
        payload = { model: model, messages: messages, temperature: @temperature, stream: false }
        body = post('/chat/completions', payload)
        content = body.dig('choices', 0, 'message', 'content')
        # Not every server answers with a String there: some hand back the
        # content as a list of parts, and a reasoning model may answer with
        # nothing but its thoughts. Both are this client's error to report,
        # rather than a NoMethodError from inside it.
        raise Error, "#{@base_url} answered without a message" unless content.is_a?(String) && !content.strip.empty?

        content
      end

      # The model to ask for. A server hosting one model still wants to be
      # told which, and the name differs with every download — so when nobody
      # has said, the loaded one is asked for by name.
      def model
        @model ||= first_loaded_model
      end

      private

      def first_loaded_model
        entry = get('/models')['data']&.first
        name = entry['id'] if entry.is_a?(Hash)
        raise Error, "no model is loaded at #{@base_url}; load one, or name it with --model" unless name

        name
      end

      def post(path, payload)
        request = Net::HTTP::Post.new(url_for(path))
        request['content-type'] = 'application/json'
        request.body = JSON.generate(payload)
        send_request(request)
      end

      def get(path)
        send_request(Net::HTTP::Get.new(url_for(path)))
      end

      def url_for(path)
        URI.parse("#{@base_url}#{path}")
      end

      def send_request(request)
        request['authorization'] = "Bearer #{@api_key}" if @api_key
        response = transport(request.uri).request(request)
        parse(response)
      # A local server generating a long answer is the one most likely to be
      # killed part way through it, and the connection dropping is how that
      # arrives here.
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE, Net::HTTPBadResponse
        raise Error, "#{@base_url} closed the connection before answering; did the model run out of memory?"
      # Everything else the network can say — refused, unreachable, no such
      # host, a route that went away — is the same thing to whoever ran the
      # command, and it is worth naming the address they can go and check.
      rescue SocketError, SystemCallError => e
        raise Error, "could not reach a model server at #{@base_url} (#{e.message}); is it running?"
      # Net::OpenTimeout and Net::ReadTimeout are both Timeout::Errors, so
      # this covers a server that accepted the connection and then thought
      # about it for too long as well as one that never accepted it.
      rescue Timeout::Error
        raise Error, "#{@base_url} did not answer within #{@timeout}s"
      end

      def transport(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http
      end

      def parse(response)
        body = begin
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          nil
        end
        raise Error, failure_message(response, body) unless response.is_a?(Net::HTTPSuccess)
        raise Error, "#{@base_url} answered with something that is not JSON" if body.nil?

        body
      end

      # An OpenAI-compatible server reports its own failures as
      # `{"error": {"message": ...}}`, and the ones that do not are quoted as
      # they came so the reason is not lost to the status code alone.
      def failure_message(response, body)
        detail = body.is_a?(Hash) ? (body.dig('error', 'message') || body['error']) : nil
        detail = response.body.to_s.strip[0, ERROR_BODY_LIMIT] if detail.nil? || detail.to_s.empty?
        "#{@base_url} answered #{response.code}#{": #{detail}" unless detail.to_s.empty?}"
      end
    end
  end
end
