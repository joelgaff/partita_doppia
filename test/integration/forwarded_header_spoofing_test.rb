require "test_helper"

# GHSA-2gff-2mmg-m73p. Under Rack 3, Rails 8.1.0 to 8.1.4 read a client-supplied
# Forwarded header ahead of the X-Forwarded-For the proxy appended, so a visitor
# could pick their own request.remote_ip, the address the request log records.
# The app keeps ip_spoofing_check on, so after the fix a disagreement between the
# two headers is refused with IpSpoofAttackError. Either secure outcome passes:
# the request is refused, or remote_ip is the address the proxy saw.
class ForwardedHeaderSpoofingTest < ActionDispatch::IntegrationTest
  REAL_CLIENT = "203.0.113.9"
  SPOOFED     = "198.51.100.7"

  setup { sign_in_as_launchpad_user(organizations(:one)) }

  test "a client-supplied Forwarded header cannot pick the visitor ip" do
    assert_includes [ REAL_CLIENT, :refused ], remote_ip_through_proxy("for=#{SPOOFED}")
  end

  test "rotating Forwarded values never put a chosen address on the request" do
    seen = (1..5).map { |i| remote_ip_through_proxy("for=198.51.100.#{i}") }

    assert_empty seen - [ REAL_CLIENT, :refused ]
  end

  test "the request log names the address the proxy saw, not the one in Forwarded" do
    started = capture_log { remote_ip_through_proxy("for=#{SPOOFED}") }[/^Started .*$/].to_s

    assert_no_match(/ for #{Regexp.escape(SPOOFED)} /, started)
  end

  test "a Forwarded header that agrees with the proxy is still served" do
    assert_equal REAL_CLIENT, remote_ip_through_proxy("for=#{REAL_CLIENT}")
    assert_response :success
  end

  private

  # A request as a proxy delivers it: X-Forwarded-For carries the client the
  # proxy saw, Forwarded is whatever the client sent and the proxy passed on.
  def remote_ip_through_proxy(forwarded)
    get root_path, headers: { "X-Forwarded-For" => REAL_CLIENT, "Forwarded" => forwarded }
    request.remote_ip
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    :refused
  end

  def capture_log
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(sink)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end
end
