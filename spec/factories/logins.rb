FactoryBot.define do
  factory :login do
    user
    roles      { user.roles }
    ip         { Faker::Internet.ip_v4_address }
    created_at { Time.now.days_ago(rand(100)) }
    error      { nil }
  end
end
