# A share link's token is in its path (/i/<token>), and Rails logs the path of
# every request as it starts. Parameter filtering covers the "Parameters:" line
# but not that one, so the token is struck out here.
module FilterShareTokensFromLog
  PATTERN = %r{(/i/)[^/.?"\s]+}

  def started_request_message(request)
    super.sub(PATTERN, '\1[FILTERED]')
  end
end

Rails::Rack::Logger.prepend(FilterShareTokensFromLog)
