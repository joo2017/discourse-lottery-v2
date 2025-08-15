import Component from "@glimmer/component";
import { inject as service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import I18n from "I18n";

export default class LotteryCard extends Component {
  @service site;
  @tracked timeRemaining = null;
  timer = null;

  constructor() {
    super(...arguments);
    if (this.isRunning && this.lotteryData?.draw_type === "by_time") {
      this.startCountdown();
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  get lotteryData() {
    return this.args.outletArgs.model.topic.lottery_data;
  }

  get isRunning() { return this.lotteryData?.status === "running"; }
  get isFinished() { return this.lotteryData?.status === "finished"; }
  get isCancelled() { return this.lotteryData?.status === "cancelled"; }

  get drawConditionText() {
    try {
      if (!this.lotteryData) return "";
      
      if (this.lotteryData.draw_type === "by_time" && this.lotteryData.draw_at) {
        const date = new Date(this.lotteryData.draw_at);
        if (isNaN(date.getTime())) return I18n.t("lottery_v2.errors.invalid_date");
        const baseText = I18n.t("lottery_v2.draw_condition.by_time", { time: date.toLocaleString() });
        return this.timeRemaining && this.isRunning ? `${baseText} (${this.timeRemaining})` : baseText;

      } else if (this.lotteryData.draw_type === "by_reply") {
        const current = this.lotteryData.participating_user_count || 0;
        const target = this.lotteryData.draw_reply_count;
        return I18n.t("lottery_v2.draw_condition.by_reply_with_progress", { current, target });
      }
    } catch (e) {
      console.error("Error formatting draw condition:", e);
      return I18n.t("lottery_v2.errors.condition_format_error");
    }
    return "";
  }

  get progressPercentage() {
    if (this.lotteryData?.draw_type === "by_reply" && this.lotteryData.draw_reply_count > 0) {
      const current = this.lotteryData.participating_user_count || 0;
      const target = this.lotteryData.draw_reply_count;
      return Math.min((current / target) * 100, 100);
    }
    return 0;
  }
  
  get hasWinners() {
    return this.isFinished && this.lotteryData.winner_data?.length > 0;
  }

  startCountdown() {
    if (!this.lotteryData?.draw_at) return;
    const targetTime = new Date(this.lotteryData.draw_at).getTime();

    const update = () => {
      const diff = targetTime - new Date().getTime();
      if (diff <= 0) {
        this.timeRemaining = I18n.t("lottery_v2.countdown.finished");
        clearInterval(this.timer);
        this.timer = null;
        return;
      }
      const days = Math.floor(diff / (1000 * 60 * 60 * 24));
      const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
      const seconds = Math.floor((diff % (1000 * 60)) / 1000);

      if (days > 0) {
        this.timeRemaining = I18n.t("lottery_v2.countdown.days", { days, hours });
      } else if (hours > 0) {
        this.timeRemaining = I18n.t("lottery_v2.countdown.hours", { hours, minutes });
      } else {
        this.timeRemaining = I18n.t("lottery_v2.countdown.minutes", { minutes, seconds });
      }
    };

    update();
    this.timer = setInterval(update, 1000);
  }
}
