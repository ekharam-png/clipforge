// POST /api/feedback: see lib/feedback.ts for the schema and the rules.
import { createFeedbackHandler } from "../../../lib/feedback.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const handler = createFeedbackHandler();

export function POST(request: Request): Promise<Response> {
  return handler.POST(request);
}

export function OPTIONS(): Promise<Response> {
  return handler.OPTIONS();
}
