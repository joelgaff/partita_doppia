# Path configuration for the native apps: which paths open as modals and the like.
# Fetched before anyone signs in, so it is public; it names paths, nothing more.
class ConfigurationsController < ApplicationController
  allow_unauthenticated

  def ios_v1
    render json: NativePathConfiguration.ios_v1
  end
end
