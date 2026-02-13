#[cfg(feature = "p2p")]
use crate::error::MBP2PError;

#[cfg(feature = "p2p")]
use libp2p::{
    gossipsub, identity,
    swarm::{Swarm, SwarmEvent},
    Multiaddr, PeerId,
};

#[cfg(feature = "p2p")]
use std::time::Duration;

/// Minimal libp2p gossipsub participation scaffold.
///
/// This is not a full node implementation; it exists to demonstrate:
/// - canonical topic naming
/// - message publishing of MBP2P envelopes
/// - subscription patterns for categories and help streams
///
/// Production implementations should add:
/// - store-and-forward relays
/// - message validation hooks (schema + signature + proof)
/// - persistence + indexing
#[cfg(feature = "p2p")]
pub struct AntennaP2P {
    pub peer_id: PeerId,
    pub swarm: Swarm<gossipsub::Behaviour>,
}

#[cfg(feature = "p2p")]
impl AntennaP2P {
    pub fn new(listen: Option<Multiaddr>) -> Result<Self, MBP2PError> {
        let local_key = identity::Keypair::generate_ed25519();
        let peer_id = PeerId::from(local_key.public());

        let gossipsub_config = gossipsub::ConfigBuilder::default()
            .heartbeat_interval(Duration::from_secs(1))
            .validation_mode(gossipsub::ValidationMode::Permissive)
            .build()
            .map_err(|e| MBP2PError::Crypto(e.to_string()))?;

        let mut behaviour = gossipsub::Behaviour::new(
            gossipsub::MessageAuthenticity::Signed(local_key),
            gossipsub_config,
        ).map_err(|e| MBP2PError::Crypto(e.to_string()))?;

        // Default to allow all topics.
        behaviour.set_allow_self_origin(false);

        let transport = libp2p::tokio_development_transport(identity::Keypair::generate_ed25519())
            .map_err(|e| MBP2PError::Crypto(e.to_string()))?;

        let mut swarm = Swarm::with_tokio_executor(transport, behaviour, peer_id);

        if let Some(addr) = listen {
            swarm.listen_on(addr).map_err(|e| MBP2PError::Crypto(e.to_string()))?;
        }

        Ok(Self { peer_id, swarm })
    }

    pub fn subscribe(&mut self, topic: &str) {
        let t = gossipsub::IdentTopic::new(topic.to_string());
        let _ = self.swarm.behaviour_mut().subscribe(&t);
    }

    pub fn publish(&mut self, topic: &str, bytes: Vec<u8>) -> Result<(), MBP2PError> {
        let t = gossipsub::IdentTopic::new(topic.to_string());
        self.swarm
            .behaviour_mut()
            .publish(t, bytes)
            .map_err(|e| MBP2PError::Crypto(e.to_string()))?;
        Ok(())
    }
}
