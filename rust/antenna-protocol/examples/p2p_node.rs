#[cfg(feature = "p2p")]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    use antenna_protocol::{topics, p2p::AntennaP2P};
    use libp2p::Multiaddr;

    let addr: Multiaddr = "/ip4/0.0.0.0/tcp/0".parse()?;
    let mut node = AntennaP2P::new(Some(addr))?;

    let topic = topics::category_topic("ai.antenna.eth");
    node.subscribe(&topic);

    println!("PeerId: {}", node.peer_id);
    println!("Subscribed: {}", topic);

    use futures::StreamExt;

    loop {
        match node.swarm.select_next_some().await {
            _ev => {
                // For a real node: handle incoming messages, validate MBEnvelope, persist events, etc.
            }
        }
    }
}

#[cfg(not(feature = "p2p"))]
fn main() {
    eprintln!("Enable the `p2p` feature to run this example:");
    eprintln!("  cargo run --example p2p_node --features p2p");
}
