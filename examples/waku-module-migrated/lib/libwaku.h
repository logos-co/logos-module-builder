/**
 * @file libwaku.h
 * @brief C API for libwaku - Waku network protocol library
 * 
 * This is a simplified header showing the essential libwaku functions.
 * In a real deployment, this would be the actual libwaku.h from nwaku.
 */

#ifndef LIBWAKU_H
#define LIBWAKU_H

#ifdef __cplusplus
extern "C" {
#endif

// Return codes
#define RET_OK 0
#define RET_ERR 1
#define RET_MISSING_CALLBACK 2

// Callback function type
typedef void (*WakuCallBack)(int ret_code, const char* msg, void* user_data);

/**
 * @brief Create a new Waku node
 * @param config_json Configuration JSON string
 * @param callback Callback for initialization result
 * @param user_data User data passed to callback
 * @return Waku context pointer, or NULL on failure
 */
void* waku_new(const char* config_json, WakuCallBack callback, void* user_data);

/**
 * @brief Start the Waku node
 * @param ctx Waku context
 * @param callback Callback for start result
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_start(void* ctx, WakuCallBack callback, void* user_data);

/**
 * @brief Stop the Waku node
 * @param ctx Waku context
 * @param callback Callback for stop result
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_stop(void* ctx, WakuCallBack callback, void* user_data);

/**
 * @brief Set the event callback
 * @param ctx Waku context
 * @param callback Callback for events
 * @param user_data User data passed to callback
 */
void waku_set_event_callback(void* ctx, WakuCallBack callback, void* user_data);

/**
 * @brief Subscribe to relay messages on a pubsub topic
 * @param ctx Waku context
 * @param pubsub_topic Pubsub topic to subscribe to
 * @param callback Callback for subscription result and messages
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_relay_subscribe(void* ctx, const char* pubsub_topic,
                          WakuCallBack callback, void* user_data);

/**
 * @brief Publish a message via relay
 * @param ctx Waku context
 * @param pubsub_topic Pubsub topic
 * @param message Base64-encoded message payload
 * @param content_topic Content topic
 * @param timeout_ms Timeout in milliseconds (0 for default)
 * @param callback Callback for publish result
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_relay_publish(void* ctx, const char* pubsub_topic,
                        const char* message, const char* content_topic,
                        int timeout_ms, WakuCallBack callback, void* user_data);

/**
 * @brief Subscribe via filter protocol
 * @param ctx Waku context
 * @param pubsub_topic Pubsub topic
 * @param content_topics_json JSON array of content topics
 * @param callback Callback for subscription result and messages
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_filter_subscribe(void* ctx, const char* pubsub_topic,
                           const char* content_topics_json,
                           WakuCallBack callback, void* user_data);

/**
 * @brief Query the store protocol
 * @param ctx Waku context
 * @param query_json Query parameters as JSON
 * @param callback Callback for query results
 * @param user_data User data passed to callback
 * @return RET_OK on success
 */
int waku_store_query(void* ctx, const char* query_json,
                      WakuCallBack callback, void* user_data);

/**
 * @brief Free the Waku context
 * @param ctx Waku context to free
 */
void waku_free(void* ctx);

#ifdef __cplusplus
}
#endif

#endif // LIBWAKU_H
