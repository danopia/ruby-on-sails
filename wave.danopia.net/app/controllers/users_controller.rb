class UsersController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update, :index]
  before_filter :connect_remote, :only => :show
  
  def new
    @user = User.new
  end
  
  def create
    params[:user].delete(:id) if params[:user]
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Account registered successfully. You may now wave."
      redirect_back_or_default '/'
    else
      render :action => :new
    end
  end
  
  # GET /users
  # GET /users.xml
  def index
    @users = User.all
    @page_title = 'User list'

    respond_to do |format|
      format.html # index.html.erb
      #format.xml  { render :xml => @users }
    end
  end

  # GET /users/1
  # GET /users/1.xml
  def show
    @user = User.find(params[:id]) || @current_user
    #@posts = @user.posts
    #@posts.sort! { |a,b| b.created_at <=> a.created_at }
    @page_title = 'User profile'

    render :action => 'show_self' if @user == @current_user
  end

  def edit
    @user = @current_user
  end
  
  def update
    @user = @current_user # makes our views "cleaner" and more consistent
    if @user.update_attributes(params[:user])
      flash[:notice] = "Your profile has been updated successfully."
      redirect_to account_url
    else
      render :action => :edit
    end
  end
end
