LotteryV2::Engine.routes.draw do
  # This file is intentionally left blank if no public routes are needed.
end

Discourse::Application.routes.draw do
  mount ::LotteryV2::Engine, at: "/lottery-v2"
  get '/admin/plugins/lottery-v2' => 'admin/lottery_admin#index', constraints: StaffConstraint.new
  put '/admin/plugins/lottery-v2/settings' => 'admin/lottery_admin#update_settings', constraints: StaffConstraint.new
end
