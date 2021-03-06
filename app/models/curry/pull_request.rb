class Curry::PullRequest < ActiveRecord::Base
  belongs_to :repository
  has_many :pull_request_updates, dependent: :destroy

  has_many :pull_request_commit_authors, dependent: :destroy
  has_many :commit_authors, through: :pull_request_commit_authors

  validates :number, presence: true
  validates :repository_id, presence: true

  scope :numbered, ->(number) { where(number: number.to_s) }

  def unknown_commit_authors
    commit_authors.where(signed_cla: false)
  end
end
