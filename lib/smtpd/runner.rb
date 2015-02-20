require_relative 'server'
module Smtpd
  class Runner
    USAGE = 'Usage: smtpd port'

    def initialize(argv)
      @port = Integer(argv.join(''), 10)
    rescue ArgumentError
      puts USAGE
      exit(-1)
    end
    
    def run
      server = SmtpServer.new(@port)
      server.audit = true
      server.debug = true
      server.start
      server.join
    end
  end
end
