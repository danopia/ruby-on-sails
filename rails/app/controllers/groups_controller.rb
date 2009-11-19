class GroupsController < ApplicationController
	before_filter :require_user, :except => ['index', 'show']
	#before_filter :connect_remote
	
  # GET /groups
  # GET /groups.xml
  def index
    @groups = Group.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @groups }
    end
  end

  # GET /groups/1
  # GET /groups/1.xml
  def show
    @group = Group.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /groups/new
  # GET /groups/new.xml
  def new
    @group = Group.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /groups/1/edit
  def edit
    @group = Group.find(params[:id])
    
    if @group.user != current_user
      flash[:error] = "You can only edit groups that belong to you."
      redirect_to @group
      return
    end
  end

  # POST /groups/1/add
  # POST /groups/1/add.xml
  def add_member
    @group = Group.find(params[:id])
    
    if @group.user != current_user
      flash[:error] = "You can only add users to groups that belong to you."
      redirect_to groups_path
      return
    end
    
    @user = User.find_by_login params[:username]
    
    if @user.nil?
      flash[:error] = "Unable to find that user."
      redirect_to groups_path
      return
    end
    
    @membership = @group.memberships.build
    @membership.user = @user

    respond_to do |format|
      if @membership.save
        flash[:notice] = "Successfully added #{@membership.user.public_name} to the group."
        format.html { redirect_to(@group) }
        format.xml  { render :xml => @membership, :status => :created, :location => @group }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # POST /groups
  # POST /groups.xml
  def create
    @group = Group.new(params[:group])
    @group.user = current_user
    
    @membership = @group.memberships.build
    @membership.user = current_user
    @membership.level = 10

    respond_to do |format|
      if @group.save && @membership.save
        flash[:notice] = 'Group was successfully created.'
        format.html { redirect_to(@group) }
        format.xml  { render :xml => @group, :status => :created, :location => @group }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /groups/1
  # PUT /groups/1.xml
  def update
    @group = Group.find(params[:id])
    
    if @group.user != current_user
      flash[:error] = "You can only edit groups that belong to you."
      redirect_to groups_path
      return
    end

    respond_to do |format|
      if @group.update_attributes(params[:group])
        flash[:notice] = 'Group was successfully updated.'
        format.html { redirect_to(@group) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /groups/1
  # DELETE /groups/1.xml
  def destroy
    @group = Group.find(params[:id])
    
    if @group.user != current_user
      flash[:error] = "You can only delete groups that belong to you."
      redirect_to groups_path
      return
    end
    
    @group.destroy

    respond_to do |format|
      format.html { redirect_to(groups_url) }
      format.xml  { head :ok }
    end
  end
end
