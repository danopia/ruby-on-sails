class CreateLotsaTables < ActiveRecord::Migration
  def self.up
    create_table :servers do |t|
      t.string      :domain,    :null => false
      t.string      :jid
      t.string      :signer_id

      t.timestamps
    end
    
    create_table :contacts do |t|
      t.integer    :user1_id,   :null => false
      t.integer    :user2_id # internal
      t.string     :user2_address # external
    end
    
    
    create_table :groups do |t|
      t.references :user
      
      t.string     :address,    :null => false
      t.string     :title,      :null => false
      t.text       :description
      t.boolean    :public
    end
    
    create_table :memberships do |t|
      t.references :user # internal
      t.references :group,      :null => false
      
      t.string     :address # external
      t.integer    :level,      :default => 1
    end
    
    
    create_table :waves do |t|
      t.references :server # host, nil=local
      
      t.string     :name,       :null => false
      t.boolean    :public,     :default => false

      t.timestamps
    end
    
    create_table :deltas do |t|
      t.references :wave,       :null => false
      t.references :server # host, nil=local
      t.references :user # author, if local
      
      t.string     :author,     :null => false
      t.string     :signer_id,  :null => false
      t.string     :raw
      t.string     :signature

      t.timestamps
    end
  end

  def self.down
    drop_table :servers
    drop_table :contacts
    drop_table :groups
    drop_table :memberships
    drop_table :waves
    drop_table :deltas
  end
end
