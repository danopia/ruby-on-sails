class ApplicationController < ActionController::Base
	helper :all
	helper_method :current_user_session, :current_user, 'logged_in?'
	filter_parameter_logging :password, :password_confirmation
	
	private

  def logged_in?
		return current_user ? true : false
	end
	
	def require_user
		unless current_user
			store_location
			flash[:notice] = "You must be logged in to access this page"
			redirect_to login_path
			return false
		end
	end

	def require_no_user
		if current_user
			store_location
			flash[:notice] = "You must be logged out to access this page"
			redirect_to logout_path
			return false
		end
	end
	
	def store_location
		session[:return_to] = request.request_uri
	end

	def redirect_back_or_default(default)
		redirect_to(session[:return_to] || default)
		session[:return_to] = nil
	end
	def redirect_back
		redirect_to(session[:return_to]) if session[:return_to]
		redirect_to(:controller => 'user', :action => 'welcome') unless session[:return_to]
		session[:return_to] = nil
	end
  def stored_redirect?
    session[:return_to]
  end
	
	def current_user_session
		return @current_user_session if defined?(@current_user_session)
		@current_user_session = UserSession.find
	end
	def current_user
		return @current_user if defined?(@current_user)
		@current_user = current_user_session && current_user_session.user
	end
	
	def connect_remote
		unless @remote
			@remote = SailsRemote.connect
			DRb.start_service
		end
		
		@address = "#{current_user.login}@#{@remote.provider.domain}"
	end
end
