require 'active_model/validations/chef_version_constraint_validator'

class CookbookDependency < ActiveRecord::Base
  # Associations
  # --------------------
  belongs_to :cookbook_version
  belongs_to :cookbook

  # Validations
  # --------------------
  validates :name, presence: true
  validates :cookbook_version, presence: true
  validates :version_constraint, chef_version_constraint: true
end
