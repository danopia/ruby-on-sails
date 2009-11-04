ActionController::Routing::Routes.draw do |map|
  # The priority is based upon order of creation: first created -> highest priority.

	#map.domain_wave 'waves/:domain/:id', :controller => 'waves', :action => 'show'
	map.waves 'waves', :controller => 'waves', :action => 'index'
	map.wave 'waves/:id', :controller => 'waves', :action => 'show'
	
	map.wave_add 'waves/:id/add', :controller => 'waves', :action => 'add'
	map.wave_remove 'waves/:id/remove/:who', :controller => 'waves', :action => 'remove',
	  :requirements => { :who => %r([^/;,?]+) }

	map.wave_update 'waves/:id/update', :controller => 'waves', :action => 'update'
	map.wave_ajax 'ajax/waves/:id', :controller => 'waves', :action => 'ajax'
	map.domain_wave 'waves/:domain/:id', :controller => 'waves', :action => 'show',
	  :requirements => { :domain => %r([^/;,?]+) }
  
  map.login 'login', :controller => 'user_sessions', :action => 'new'
  map.logout 'logout', :controller => 'user_sessions', :action => 'destroy'
  
	map.resource :account, :controller => 'users'
	map.resources :users
  map.resource :user_session
	
  map.root :controller => 'waves', :action => 'index'

  # Sample of regular route:
  #   map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action
	
  # Sample of named route:
  #   map.purchase 'products/:id/purchase', :controller => 'catalog', :action => 'purchase'
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   map.resources :products

  # Sample resource route with options:
  #   map.resources :products, :member => { :short => :get, :toggle => :post }, :collection => { :sold => :get }

  # Sample resource route with sub-resources:
  #   map.resources :products, :has_many => [ :comments, :sales ], :has_one => :seller
  
  # Sample resource route with more complex sub-resources
  #   map.resources :products do |products|
  #     products.resources :comments
  #     products.resources :sales, :collection => { :recent => :get }
  #   end

  # Sample resource route within a namespace:
  #   map.namespace :admin do |admin|
  #     # Directs /admin/products/* to Admin::ProductsController (app/controllers/admin/products_controller.rb)
  #     admin.resources :products
  #   end

  # You can have the root of your site routed with map.root -- just remember to delete public/index.html.
  # map.root :controller => "welcome"

  # See how all your routes lay out with "rake routes"

  # Install the default routes as the lowest priority.
  # Note: These default routes make all actions in every controller accessible via GET requests. You should
  # consider removing or commenting them out if you're using named routes and resources.
  #map.connect ':controller/:action/:id'
  #map.connect ':controller/:action/:id.:format'
end
