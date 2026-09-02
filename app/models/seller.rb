class Seller < ApplicationRecord
  has_many :seller_performance_reports
  has_many :seller_reconciliations
end
