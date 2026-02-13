pub fn category_topic(category_ens: &str) -> String {
    format!("mb/v1/cat/{}", category_ens)
}

pub fn help_topic(category_ens: &str) -> String {
    format!("mb/v1/help/{}", category_ens)
}

pub fn help_replies_topic(help_request_event_id: &str) -> String {
    format!("mb/v1/help-replies/{}", help_request_event_id)
}
