require 'gserver'
require 'mail'
require_relative 'channel'


module Smtpd
  class SmtpServer < GServer
  
    def serve(io)
      channel = SmtpChannel.new(self, io)
      channel.handle_connection
    end
  
    def process_raw_message(from, to, raw_message)
      message = Mail.read_from_string(raw_message)
      process_message(from, to, message)
    end
  
    def process_message(from, to, message)
      puts "Received message from: #{from}, to: #{to.join(', ')}"
      puts message.body
    end
  end
end
