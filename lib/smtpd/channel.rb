module Smtpd
  class SmtpChannel
    
    def initialize(server, io)
      @server = server
      @io = io
      @stdlog = server.stdlog
      @state = :command
      @read_terminator = "\r\n"
      @push_terminator = "\r\n"
      @greeting = nil
      @from = nil
      @to = []
    end
  
    def handle_connection
      push "220 #{fqdn} SMTP"
      loop do
        line = get_line
        process_line(line)
        break if @state == :quit
      end
      @io.close
    rescue Errno::EPIPE
      # client disconnected unexpectedly
    end
  
    private
  
    def get_line
      line = ""
      loop do
        IO.select([@io])
        data = @io.gets(@read_terminator)
        line << data.chomp(@read_terminator)
        break if data.end_with? @read_terminator
      end
      line.strip!
      log "<<<", line
      line
    end
  
    def process_line(line)
      case @state
        when :command then process_command(line)
        when :data then process_data(line)
      end
    end
  
    def process_command(line)
      if line.empty?
        push "500 Error: bad syntax"
        return
      end
      command = line[/\w+/].upcase
      arg = line[command.size..-1].strip
      method = "smtp_#{command}".to_sym
      if command != "HELO" && @greeting.nil?
        push "503 Error: send HELO first"
      elsif respond_to? method, true
        status = send method, arg
        push status
      else
        push "502 Error: command \"#{command}\" not implemented"
      end
    end
  
    def process_data(line)
      @data = line
      status = @server.process_raw_message(@from, @to, @data)
      status ||= "250 Ok"
      reset
      push status
    end
  
    def push(line)
      log ">>>", line
      @io.print line, @push_terminator
    end
  
    def smtp_HELO(arg)
      return "501 Syntax: HELO hostname" if arg.empty?
      return "503 Error: duplicate HELO command" if @greeting
      @greeting = arg
      "250 #{fqdn}"
    end
  
    def smtp_MAIL(arg)
      address = getaddr("FROM:", arg)
      return "501 Syntax: MAIL FROM:<address>" if address.empty?
      return "503 Error: duplicate MAIL command" unless @from.nil?
      @from = address
      "250 Ok"
    end
  
    def smtp_RCPT(arg)
      address = getaddr("TO:", arg)
      return "501 Syntax: RCPT TO: <address>" if address.empty?
      return "503 Error: need MAIL command" if @from.nil?
      @to << address
      "250 Ok"
    end
  
    def smtp_RSET(arg)
      return "501 Syntax: RSET" unless arg.empty?
      reset
      "250 Ok"
    end
  
    def smtp_DATA(arg)
      return "501 Syntax: DATA" unless arg.empty?
      return "503 Error: need RCPT command" if @to.empty?
      @state = :data
      @read_terminator = "\r\n.\r\n"
      "354 End data with <CR><LF>.<CR><LF>"
    end
  
    def smtp_NOOP(arg)
      return "501 Syntax: NOOP" unless arg.empty?
      "250 Ok"
    end
  
    def smtp_QUIT(arg)
      return "501 Syntax: QUIT" unless arg.empty?
      @state = :quit
      "221 Bye"
    end
  
    def reset
      @state = :command
      @read_terminator = "\r\n"
      @from = nil
      @to = []
      @data = ""
    end
  
    def getaddr(keyword, arg)
      return "" unless arg.downcase.start_with? keyword.downcase
      arg[keyword.size..-1].gsub(/<(.*)>/, '\1').strip
    end
  
    def log(prefix, msg)
      if @stdlog
        @stdlog.puts(msg.gsub(/^/, "[#{Time.new.ctime}] #{self.class} #{prefix} "))
        @stdlog.flush
      end
    end
  
    def fqdn
      @fqdn ||= Socket.gethostbyname(Socket.gethostname).first
    end
  end
end
