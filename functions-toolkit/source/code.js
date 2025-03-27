const gateways = {
    ipfs: ["ipfs.io", "dweb.link", "w3s.link", "gateway.pinata.cloud"],
    btfs: ["gateway.btfs.io"],
};

const tokenUri = args[0];
const traitType = args[1];

if (!tokenUri || !traitType) {
    throw Error("Token URI or trait type is empty");
}

let apiResponse;
if (tokenUri.slice(0, 8) === "https://") {
    apiResponse = await Functions.makeHttpRequest({
        url: tokenUri,
        headers: { accept: "application/json" },
    });

    if (apiResponse.error) {
        console.error(apiResponse.error);
        throw Error("Request failed");
    }
} else {
    const urlParts = tokenUri.split("://");
    const protocol = urlParts[0];
    const suburl = urlParts[1];
    for (const gateway of gateways[protocol]) {
        const uri = `https://${gateway}/${protocol}/${suburl}`;

        try {
            apiResponse = await Functions.makeHttpRequest({
                url: uri,
                headers: { accept: "application/json" },
            });
            if (apiResponse.error) {
                console.error(apiResponse.error);
                throw Error("Request failed");
            }
            break;
        } catch (error) {
            console.error(error);
        }
    }
}
const { data } = apiResponse;
if (!data.attributes) {
    throw Error("Metadata does not contain any traits.");
}
let traitValue = null;
for (let i = 0; i < data.attributes.length; i++) {
    if (data.attributes[i].trait_type == traitType) {
        traitValue = data.attributes[i].value;
    }
}
if (traitValue == null) {
    throw Error("Trait not found.");
}
return Functions.encodeString(traitValue);