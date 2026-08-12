# frozen_string_literal: true

require_relative '../error'
require_relative '../null_logger'
require_relative '../parser'
require_relative 'client'
require_relative 'prompt'

module Btape
  module LLM
    # Turns a description of a recording into a tape, by asking a model for
    # one and then holding it to the language: what comes back is parsed
    # before it is handed on, and a reply that does not parse goes back with
    # the parser's complaint attached.
    #
    # That loop is the point of generating a tape rather than pasting one out
    # of a chat window. A small local model reliably invents a command or
    # forgets a quote; it just as reliably fixes it when told which line.
    class Generator
      ATTEMPTS = 3

      # Models are told not to fence their answer, and fence it anyway.
      FENCED = /```[\w+-]*\n(.*?)```/m

      def initialize(client: Client.new, attempts: ATTEMPTS, logger: NullLogger.new)
        @client = client
        @attempts = attempts
        @logger = logger
      end

      # Returns the tape as a String. Raises LLM::Error if the model could not
      # be reached, or would not produce a tape that parses.
      def call(description, context: nil)
        raise Error, 'nothing was said about what to record' if description.to_s.strip.empty?

        messages = [
          { role: 'system', content: Prompt.system },
          { role: 'user', content: Prompt.user(description.strip, context: context) }
        ]
        attempt(messages)
      end

      private

      def attempt(messages)
        reason = nil
        @attempts.times do |index|
          @logger.debug("btape: asking #{@client.model} for a tape (attempt #{index + 1} of #{@attempts})")
          script = extract(@client.complete(messages))
          reason = fault(script)
          return script if reason.nil?

          @logger.debug("btape: the tape did not parse (#{reason}); asking again")
          messages += [{ role: 'assistant', content: script }, { role: 'user', content: Prompt.repair(reason) }]
        end
        raise Error, "the model did not write a tape that parses, after #{@attempts} attempts: #{reason}"
      end

      # Why this is not a tape, or nil when it is one. The parser answers most
      # of it; Output is checked here because it is the one requirement that
      # belongs to the script as a whole rather than to any line of it, and a
      # tape without it fails at the start of a recording instead.
      def fault(script)
        commands = Parser.new.parse(script)
        return 'it contained no commands' if commands.empty?
        unless commands.any? { |command| command.name == 'Output' }
          return 'it has no Output line, so there is nowhere for the GIF to go'
        end

        nil
      rescue ScriptError => e
        e.message
      end

      # The tape out of the reply. A fenced block is taken as the answer and
      # any prose around it dropped; everything else is passed through whole,
      # so that a stray sentence reaches the parser and comes back as
      # something the model is asked to fix.
      def extract(reply)
        match = FENCED.match(reply)
        "#{(match ? match[1] : reply).strip}\n"
      end
    end
  end
end
