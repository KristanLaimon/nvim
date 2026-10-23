---
name: Custom Hook
description: React custom hook with state and lifecycle
index: 6
---
import { useCallback, useEffect, useState } from "react";

export interface Use<%filename%>Options {
	$0
}

export function use<%filename%>(options?: Use<%filename%>Options) {
	const [value, setValue] = useState<unknown>(null);

	const reset = useCallback(() => {
		setValue(null);
	}, []);

	useEffect(() => {
	}, []);

	return {
		value,
		setValue,
		reset,
	};
}
