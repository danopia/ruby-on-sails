class UsersController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  
  def new
    @user = User.new
  end
  
  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Account registered!"
      redirect_back_or_default account_url
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

  #~ # GET /users/1
  #~ # GET /users/1.xml
  #~ def show
    #~ @user = User.find(params[:id])
    #~ @posts = @user.posts
    #~ @posts.sort! { |a,b| b.created_at <=> a.created_at }
    #~ @page_title = 'User profile'
#~ 
    #~ respond_to do |format|
      #~ format.html # show.html.erb
      #~ #format.xml  { render :xml => @user }
    #~ end
  #~ end
  
  def show
    @user = @current_user
  end

  def edit
    @user = @current_user
  end
  
  def update
    @user = @current_user # makes our views "cleaner" and more consistent
    if @user.update_attributes(params[:user])
      flash[:notice] = "Account updated!"
      redirect_to account_url
    else
      render :action => :edit
    end
  end
end
