---
name: Function Component (Hooks, no props)
description: React function component with useState/useEffect hooks
index: 1
---
import { useEffect, useState } from "react";

export function <%filename%>() {
	const [count, setCount] = useState<number>(0);

	useEffect(() => {
		$0
	}, []);

	return (
		<div>
			<p>{count}</p>
			<button onClick={() => setCount((prev) => prev + 1)}>Increment</button>
		</div>
	);
}
