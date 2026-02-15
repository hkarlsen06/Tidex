-- Add triggers for feedback_responded and share_started notifications
-- These make DB triggers the single source for enqueuing these notification types

DROP TRIGGER IF EXISTS a_on_feedback_responded_notify ON public.feedback;
CREATE TRIGGER a_on_feedback_responded_notify
  AFTER UPDATE ON public.feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_feedback_responded_notification();

DROP TRIGGER IF EXISTS on_share_started_notify ON public.shift_shares;
CREATE TRIGGER on_share_started_notify
  AFTER INSERT ON public.shift_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_share_started_notification();;
