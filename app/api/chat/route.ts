/**
 * Wagey Chat API Endpoint
 *
 * Handles streaming chat requests with tool calling
 */

import { riverEndpointHandler } from "@/lib/river";
import { chatRouter } from "@/lib/chat/router";

// Create River endpoint handlers
const { GET, POST } = riverEndpointHandler(chatRouter);

export { GET, POST };
