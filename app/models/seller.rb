class Seller < ApplicationRecord
  has_many :seller_performance_reports, dependent: :restrict_with_exception
  has_many :seller_reconciliations, dependent: :restrict_with_exception
end
