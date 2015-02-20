require 'socket'
require 'test/unit'
require 'mocha/test_unit'
require_relative '../lib/smtpd/channel'

class TestChannel < Test::Unit::TestCase
  
  def setup
    @server = server_mock
    @server_thread = Thread.new do
      server = TCPServer.new("127.0.0.1", 62897)
      io = server.accept
      server.close
      channel = Smtpd::SmtpChannel.new(@server, io)
      channel.stubs(:fqdn).returns("example.com")
      channel.handle_connection
    end
    begin
      @io = TCPSocket.new("127.0.0.1", 62897)
    rescue Errno::ECONNREFUSED
      retry
    end  
  end
  
  def server_mock
    server = mock()
    server.stubs(:stdlog).returns(nil)
    return server
  end
  
  def teardown
    @server_thread.terminate if @server_thread.join(0).nil?
    @io.close unless @io.closed?
  end
  
  def C line
    @io.print "#{line}\r\n"
  end
  
  def S line
    assert_equal "#{line}\r\n", @io.gets
  end
  
  def test_simple_message
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end

  def test_addresses_in_brackets
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL FROM: <alice@example2.com>"
    S "250 Ok"
    C "RCPT TO: <bob@example.com>"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_multiple_recipents
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com", "tom@example.com", "jim@example.com"], "some message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "RCPT TO: tom@example.com"
    S "250 Ok"
    C "RCPT TO: jim@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_noop
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "NOOP"
    S "250 Ok"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "NOOP"
    S "250 Ok"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "NOOP"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_reset
    @server.expects(:process_raw_message).with("greg@example2.com", ["jim@example.com"], "some message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "RSET"
    S "250 Ok"
    C "MAIL FROM: greg@example2.com"
    S "250 Ok"
    C "RCPT TO: jim@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_multiple_messages
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    @server.expects(:process_raw_message).with("greg@example2.com", ["jim@example.com"], "another message")
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "MAIL FROM: greg@example2.com"
    S "250 Ok"
    C "RCPT TO: jim@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "another message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_disconnect
    S "220 example.com SMTP"
    C "HELO example2.com"
    @io.close
    fail until @server_thread.join(1)
  end
  
  def test_syntax_errors
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    S "220 example.com SMTP"
    C ""
    S "500 Error: bad syntax"
    C "HELO"
    S "501 Syntax: HELO hostname"
    C "HELO example2.com"
    S "250 example.com"
    C "MAIL alice@example2.com"
    S "501 Syntax: MAIL FROM:<address>"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "RCPT bob@example.com"
    S "501 Syntax: RCPT TO: <address>"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "RSET arg"
    S "501 Syntax: RSET"
    C "NOOP arg"
    S "501 Syntax: NOOP"
    C "QUIT arg"
    S "501 Syntax: QUIT"
    C "DATA arg"
    S "501 Syntax: DATA"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_wrong_command_sequence
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    S "220 example.com SMTP"
    C "MAIL FROM: alice@example2.com"
    S "503 Error: send HELO first"
    C "HELO example2.com"
    S "250 example.com"
    C "DATA"
    S "503 Error: need RCPT command"
    C "RCPT TO: bob@example.com"
    S "503 Error: need MAIL command"
    C "MAIL FROM: alice@example2.com"
    S "250 Ok"
    C "MAIL FROM: tom@example2.com"
    S "503 Error: duplicate MAIL command"
    C "RCPT TO: bob@example.com"
    S "250 Ok"
    C "DATA"
    S "354 End data with <CR><LF>.<CR><LF>"
    C "some message\r\n."
    S "250 Ok"
    C "QUIT"
    S "221 Bye"
  end
  
  def test_command_not_implemented
    S "220 example.com SMTP"
    C "HELO example2.com"
    S "250 example.com"
    C "BLAH arg"
    S "502 Error: command \"BLAH\" not implemented"
    C "QUIT"
    S "221 Bye"
  end
end
