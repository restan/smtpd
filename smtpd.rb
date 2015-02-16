require 'gserver'
require 'mail'


class SmtpServer < GServer

  def serve(io)
    channel = SmtpChannel.new(self, io, @debug)
    channel.handle_connection
  end

  def process_raw_message(from, to, raw_message)
    message = Mail.read_from_string(raw_message)
    process_message(from, to, message)
  end

  def process_message(from, to, message)
    puts "Received message from: #{from}, to: #{to.join(',')}"
    puts message.body
  end
end


class SmtpChannel
  
  def initialize(server, io, debug)
    @server = server
    @io = io
    @debug = debug
    @state = :command
    @terminator = "\r\n"
    @greeting = nil
    @from = nil
    @to = []
  end

  def handle_connection
    push "220 #{fqdn} SMTP TempMail"
    loop do
      line = get_line
      process_line(line)
      break if (@state == :quit || @io.closed?)
    end
    @io.close
  end

  private

  def get_line
    line = ""
    loop do
      IO.select([@io])
      data = @io.gets(@terminator)
      line << data.chomp(@terminator)
      break if data.end_with? @terminator
    end
    line.strip!
    log "<<< #{line}"
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
    if respond_to? method, true
      status = send method, arg
      push status unless status.empty?
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
    log ">>> #{line}"
    @io.print line, @terminator
  end

  def smtp_HELO(arg)
    return "501 Syntax: HELO hostname" if arg.empty?
    return "503 Duplicate HELO/EHLO" if @greeting
    @greeting = arg
    "250 #{fqdn}"
  end

  def smtp_MAIL(arg)
    address = getaddr("FROM:", arg)
    return "501 Syntax: MAIL FROM:<address>" if address.empty?
    return "503 Error: nested MAIL command" unless @from.nil?
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
    @terminator = "\r\n.\r\n"
    "354 End data with <CR><LF>.<CR><LF>"
  end

  def smtp_QUIT(arg)
    return "501 Syntax: QUIT" unless arg.empty?
    @state = :quit
    "221 Bye"
  end

  def reset
    @state = :command
    @terminator = "\r\n"
    @from = nil
    @to = []
    @data = ""
  end

  def getaddr(keyword, arg)
    return "" unless arg.downcase.start_with? keyword.downcase
    arg[keyword.size..-1].gsub(/<(.*)>/, '\1').strip
  end

  def log(msg)
    puts msg if @debug
  end

  def fqdn
    @fqdn ||= Socket.gethostbyname(Socket.gethostname).first
  end
end

server = SmtpServer.new(2525)
server.audit = true
server.debug = true
server.start
server.join

