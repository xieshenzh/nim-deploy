- Create secret for pulling the image: 
  ```
  oc create secret docker-registry ngc-secret \
  --docker-server=nvcr.io\
  --docker-username='$oauthtoken'\
  --docker-password=${NGC_API_KEY}
  ```
  
- Enter the api key in `secret.yaml`. Apply `secret.yaml`, `pvc.yaml` and `job.yaml`.

- Use the pod logs and terminal to check if the model is downloaded. Check the PVC if model has been downloaded.

- Delete the job when the pod finished downloading the model.