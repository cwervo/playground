import * as THREE from "three";

function main() {
	const renderer = new THREE.WebGLRenderer({ antialias: true });
	renderer.setSize(window.innerWidth, window.innerHeight);
	document.body.appendChild(renderer.domElement);

	const fov = 75;
	const aspect = window.innerWidth / window.innerHeight;
	const near = 0.1;
	const far = 1000;
	const camera = new THREE.PerspectiveCamera(fov, aspect, near, far);
	camera.position.z = 5;

	const scene = new THREE.Scene();

	const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
	scene.add(ambientLight);

	const directionalLight = new THREE.DirectionalLight(0xffffff, 0.5);
	directionalLight.position.set(0, 1, 1);
	scene.add(directionalLight);

	const geometry = new THREE.CylinderGeometry(1, 1, 10, 64, 64);
	const material = new THREE.MeshPhongMaterial({
		color: 0xaaaaaa,
		shininess: 100,
	});
	const cylinder = new THREE.Mesh(geometry, material);
	scene.add(cylinder);

	const notchGeometry = new THREE.BoxGeometry(0.1, 0.1, 1.1);
	const notchMaterial = new THREE.MeshPhongMaterial({ color: 0xff0000 });
	const photoMaterial = new THREE.MeshBasicMaterial({
		map: new THREE.TextureLoader().load("https://picsum.photos/200/300"),
	});

	for (let i = 0; i < 60; i++) {
		const angle = (i / 60) * Math.PI * 2;
		if (i % 5 === 0) {
			const photoGeometry = new THREE.PlaneGeometry(0.8, 0.5);
			const photo = new THREE.Mesh(photoGeometry, photoMaterial);
			photo.position.x = Math.cos(angle) * 1.1;
			photo.position.z = Math.sin(angle) * 1.1;
			photo.rotation.y = -angle;
			cylinder.add(photo);
		} else {
			const notch = new THREE.Mesh(notchGeometry, notchMaterial);
			notch.position.x = Math.cos(angle) * 1.05;
			notch.position.z = Math.sin(angle) * 1.05;
			notch.rotation.y = -angle;
			cylinder.add(notch);
		}
	}

	let isDragging = false;
	let previousMousePosition = {
		x: 0,
		y: 0,
	};

	renderer.domElement.addEventListener("mousedown", (e) => {
		isDragging = true;
	});
	renderer.domElement.addEventListener("mouseup", (e) => {
		isDragging = false;
	});
	renderer.domElement.addEventListener("mousemove", (e) => {
		const deltaMove = {
			x: e.offsetX - previousMousePosition.x,
			y: e.offsetY - previousMousePosition.y,
		};

		if (isDragging) {
			const deltaRotationQuaternion = new THREE.Quaternion().setFromEuler(
				new THREE.Euler(
					(deltaMove.y * Math.PI) / 180,
					(deltaMove.x * Math.PI) / 180,
					0,
					"XYZ"
				)
			);
			cylinder.quaternion.multiplyQuaternions(
				deltaRotationQuaternion,
				cylinder.quaternion
			);
		}

		previousMousePosition = {
			x: e.offsetX,
			y: e.offsetY,
		};
	});

	renderer.domElement.addEventListener("wheel", (e) => {
		camera.position.z += e.deltaY * 0.01;
	});

	function animate() {
		requestAnimationFrame(animate);
		renderer.render(scene, camera);
	}

	animate();
}

main();
