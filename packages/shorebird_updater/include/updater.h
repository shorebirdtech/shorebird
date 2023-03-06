#ifndef updater_h
#define updater_h

#ifdef __cplusplus
extern "C"
{
#endif

    char *active_version(const char *client_id, const char *cache_dir);
    char *active_path(const char *client_id, const char *cache_dir);
    bool check_for_update(const char *client_id, const char *cache_dir);
    void update(const char *client_id, const char *cache_dir);

    void free_string(char *str);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* updater_h */
