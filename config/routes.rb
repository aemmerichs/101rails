Wiki::Application.routes.draw do

  # homepage
  root :to => "application#landing_page"
  # sitemap
  get '/sitemap.xml' => 'application#sitemap'
  # link for downloading slides from slideshare
  get '/get_slide/*slideshare' => 'application#get_slide', :format => false

  get '/search' => 'pages#search'
  get '/contributors_without_github_name' => 'application#contributors_without_github_name'
  get '/pullRepo.json' => 'application#pull_repo'

  # admin ui
  mount RailsAdmin::Engine => '/admin', :as => 'rails_admin'

  # urls for contribution process
  scope 'contribute' do
    # ui for creating contribution
    get '/new' => 'contributions#new'
    get '/apply_findings/:id' => 'pages#apply_findings', :constraints => { :id => /.*/ }
    post '/update/:id' => 'pages#update_repo', :constraints => { :id => /.*/ }
    put '/update/:id' => 'pages#update_repo', :constraints => { :id => /.*/ }
    # method where contribution will be created
    post '/analyze/:id' => 'contributions#analyze', :constraints => { :id => /.*/ }
    post '/new' => 'contributions#create'
    get '/repo_dirs/:repo' => 'contributions#get_repo_dirs', :constraints => { :repo => /.*/ }
  end

  # tours
  scope 'tours' do
    get '/' => 'tours#index'
    match '/:title' => 'tours#show'
  end

  # tours api
  scope 'api/tours' do
    get ':title' => 'tours#show', :as => :tour
    put ':title' => 'tours#update'
    delete ':title' => 'tours#delete'
  end

  get 'users/logout' => 'authentications#destroy'

  # clones
  scope 'clones' do
    get '/new' => 'clones#show_create'
    get '/' => 'clones#show'
    get '/check/:title' => 'clones#show'
  end

  # pages routes
  scope 'wiki' do
    get '/' => redirect("/wiki/@project")
    match '/create_new_page/:id' => 'pages#create_new_page', :constraints => { :id => /.*/ }, :as => :page
    match '/create_new_page_confirmation/:id' => 'pages#create_new_page_confirmation', :constraints => { :id => /.*/ }, :as => :page
    match '/:id' => 'pages#show' , :constraints => { :id => /.*/ }, :as => :page
  end

  # routes for work with history
  scope 'page_changes' do
    get 'all/:page_id' => 'page_changes#get_all'
    # compare with current revision
    get 'diff/:page_change_id' => 'page_changes#diff'
    # compare two revisions
    get 'diff/:page_change_id/:another_page_change_id' => 'page_changes#diff'
    get 'show/:page_change_id' => 'page_changes#show'
    get 'apply/:page_change_id' => 'page_changes#apply'
  end

  # json api requests for pages
  scope 'api', :format => :json do
    # clones api
    get 'clones/:title' => 'clones#get'
    post 'clones/:title' => 'clones#create'
    put 'clones/:title' => 'clones#update'
    get 'clones/:title' => 'clones#get'
    delete 'clones/:title' => 'clones#delete'
    get 'clones' => 'clones#index'
    # pages api
    post 'parse' => 'pages#parse'
    get 'pages' => 'pages#all'
    resources :pages, :constraints => { :id => /.*/ }, :only => [:section,:show] do
      member do
        get "/" => 'pages#show'
        put "/" => 'pages#update'
        delete '/' => 'pages#delete'
        get 'sections' => 'pages#sections'
        get 'internal_links' => 'pages#internal_links'
        get 'sections/:id' => 'pages#section'
      end
    end
  end

  scope 'endpoint', :format => :json do
    get ':id/rdf' => 'pages#get_rdf', :constraints => { :id => /.*/ }
    get ':id/json' => 'pages#get_json', :constraints => { :id => /.*/ }, :directions => false
    get ':id/json/directions' => 'pages#get_json', :constraints => { :id => /.*/ }, :directions => true
    get ':id/summary' => 'pages#summary', :constraints => { :id => /.*/ }
  end

  # authentications
  scope 'auth' do
    match '/github/callback' => 'authentications#create'
    match '/failure' => 'authentications#failure'
  end
end
