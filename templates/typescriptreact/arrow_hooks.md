---
name: Arrow Function (Hooks, no props)
description: Arrow function component with useState/useEffect hooks
index: 3
---
import { useEffect, useState } from "react";

export const <%filename%> = () => {
	const [data, setData] = useState<string>("");

	useEffect(() => {
		$0
	}, []);

	return (
		<div>
			<p>{data}</p>
		</div>
	);
};
