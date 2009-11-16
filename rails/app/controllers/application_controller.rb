class ApplicationController < ActionController::Base
	helper :all
	helper_method :current_user_session, :current_user, 'logged_in?'
	filter_parameter_logging :password, :password_confirmation
	
	protected

	# Is the user currently logged in? Basically the same as +current_user+
	# except that this method always returns a boolean value.
  def logged_in?
		return current_user ? true : false
	end
	
	# Require an account. Redirects to the login page if the user is logged out.
	# Best used with before_filter.
	def require_user
		return true if current_user
	
		store_location
		flash[:notice] = "You must be logged in to access this page"
		redirect_to login_path
		false
	end

	# This is a funny little method. It requires that a user be signed out to
	# view a page, and logs them out if they are logged in.
	def require_no_user
		return true unless current_user
		
		store_location
		flash[:notice] = "You must be logged out to access this page"
		redirect_to logout_path
		false
	end
	
	# Stores the current location. Used for redirection.
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
	
	# Gets the current user's account.
	def current_user
		return @current_user if defined?(@current_user)
		@current_user = current_user_session && current_user_session.user
	end
	
	# Connect the SailsRemote. Also sets @address to the current user's address.
	def connect_remote
		@remote = Sails::Remote.connect unless @remote
		
		@address = "#{current_user.login}@#{@remote.provider.domain}" rescue nil
		@user = @remote.provider.find_or_create_user @address if @address
	end
end
