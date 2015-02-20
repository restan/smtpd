require 'socket'
require 'timeout'
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
  
  def push(line)
    @io.print line
  end
  
  def assert_next_line(line)
    assert_equal line, @io.gets
  end
  
  def test_simple_message
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end

  def test_addresses_in_brackets
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL FROM: <alice@example2.com>\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: <bob@example.com>\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_multiple_recipents
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com", "tom@example.com", "jim@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: tom@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: jim@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_noop
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "NOOP\r\n"
    assert_next_line "250 Ok\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "NOOP\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "NOOP\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_reset
    @server.expects(:process_raw_message).with("greg@example2.com", ["jim@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RSET\r\n"
    assert_next_line "250 Ok\r\n"
    push "MAIL FROM: greg@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: jim@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_multiple_messages
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    @server.expects(:process_raw_message).with("greg@example2.com", ["jim@example.com"], "another message")
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "MAIL FROM: greg@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT TO: jim@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "another message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_disconnect
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    @io.close
    fail until @server_thread.join(1)
  end
  
  def test_syntax_errors
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "\r\n"
    assert_next_line "500 Error: bad syntax\r\n"
    push "HELO\r\n"
    assert_next_line "501 Syntax: HELO hostname\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "MAIL alice@example2.com\r\n"
    assert_next_line "501 Syntax: MAIL FROM:<address>\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RCPT bob@example.com\r\n"
    assert_next_line "501 Syntax: RCPT TO: <address>\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "RSET arg\r\n"
    assert_next_line "501 Syntax: RSET\r\n"
    push "NOOP arg\r\n"
    assert_next_line "501 Syntax: NOOP\r\n"
    push "QUIT arg\r\n"
    assert_next_line "501 Syntax: QUIT\r\n"
    push "DATA arg\r\n"
    assert_next_line "501 Syntax: DATA\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_wrong_command_sequence
    @server.expects(:process_raw_message).with("alice@example2.com", ["bob@example.com"], "some message")
    assert_next_line "220 example.com SMTP\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "503 Error: send HELO first\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "DATA\r\n"
    assert_next_line "503 Error: need RCPT command\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "503 Error: need MAIL command\r\n"
    push "MAIL FROM: alice@example2.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "MAIL FROM: tom@example2.com\r\n"
    assert_next_line "503 Error: duplicate MAIL command\r\n"
    push "RCPT TO: bob@example.com\r\n"
    assert_next_line "250 Ok\r\n"
    push "DATA\r\n"
    assert_next_line "354 End data with <CR><LF>.<CR><LF>\r\n"
    push "some message\r\n.\r\n"
    assert_next_line "250 Ok\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
  
  def test_command_not_implemented
    assert_next_line "220 example.com SMTP\r\n"
    push "HELO example2.com\r\n"
    assert_next_line "250 example.com\r\n"
    push "BLAH arg\r\n"
    assert_next_line "502 Error: command \"BLAH\" not implemented\r\n"
    push "QUIT\r\n"
    assert_next_line "221 Bye\r\n"
  end
end
