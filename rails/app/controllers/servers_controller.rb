class ServersController < ApplicationController
	before_filter :require_user, :except => ['index', 'show']
	before_filter :connect_remote

  def index
		@servers = @remote.provider.servers.values.uniq
  end

  def show
  end

  def create
  end

  def waves
  end

end
